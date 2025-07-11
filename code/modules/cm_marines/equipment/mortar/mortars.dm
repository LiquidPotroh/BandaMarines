// The Marine mortar, the M402 Mortar
// Works like a contemporary crew weapon mortar
/obj/structure/mortar
	name = "\improper M402 mortar"
	desc = "A manual, crew-operated mortar system intended to rain down 80mm goodness on anything it's aimed at. Uses an advanced targeting computer, which can toggle between coordinate and laser targeting. Insert round to fire. Alt + Click to switch targeting modes."
	icon = 'icons/obj/structures/mortar.dmi'
	icon_state = "mortar_m402"
	anchored = TRUE
	unslashable = TRUE
	unacidable = TRUE
	density = TRUE
	// So you can't hide it under corpses
	layer = ABOVE_MOB_LAYER
	flags_atom = RELAY_CLICK
	var/computer_enabled = TRUE
	// Initial target coordinates
	var/targ_x = 0
	var/targ_y = 0
	var/targ_z = 0
	// Automatic offsets from target
	var/offset_x = 0
	var/offset_y = 0
	/// Number of turfs to offset from target by 1
	var/offset_per_turfs = 20
	// Dial adjustments from target
	var/dial_x = 0
	var/dial_y = 0
	/// Constant, assuming perfect parabolic trajectory. ONLY THE DELAY BEFORE INCOMING WARNING WHICH ADDS 45 TICKS
	var/travel_time = 4.5 SECONDS
	var/busy = FALSE
	/// Used for deconstruction and aiming sanity
	var/firing = FALSE
	/// If set to 1, can't unanchor and move the mortar, used for map spawns and WO
	var/fixed = FALSE
	/// if true, blows up the shell immediately
	var/ship_side = FALSE
	/// The max range the mortar can fire at
	var/max_range = 64
	/// The min range the mortar can fire at
	var/min_range = 15
	/// True if in lase mode, else in coordinate mode
	var/lase_mode = FALSE
	/// Used for lase mode aiming, busy but not used by someone else.
	var/aiming = FALSE
	/// True if mortar is ready to fire on lase mode.
	var/aimed = FALSE

	/// Linked laser designator to be used in lase mode, null if one isn't linked
	var/obj/item/device/binoculars/range/designator/linked_designator
	var/image/busy_image_aim
	var/image/busy_image_return
	var/obj/structure/machinery/computer/cameras/mortar/internal_camera

/obj/structure/mortar/Initialize()
	. = ..()
	// Makes coords appear as 0 in UI
	targ_x = deobfuscate_x(0)
	targ_y = deobfuscate_y(0)
	targ_z = deobfuscate_z(0)
	internal_camera = new(loc)

	var/new_icon_state
	switch(SSmapping.configs[GROUND_MAP].camouflage_type)
		if("classic")
			icon_state = new_icon_state ? new_icon_state : "c_" + icon_state
		if("desert")
			icon_state = new_icon_state ? new_icon_state : "d_" + icon_state
		if("snow")
			icon_state = new_icon_state ? new_icon_state : "s_" + icon_state
		if("urban")
			icon_state = new_icon_state ? new_icon_state : "u_" + icon_state

/obj/structure/mortar/Destroy()
	QDEL_NULL(internal_camera)
	return ..()

/obj/structure/mortar/initialize_pass_flags(datum/pass_flags_container/PF)
	..()
	if (PF)
		PF.flags_can_pass_all = PASS_OVER

/obj/structure/mortar/get_projectile_hit_boolean(obj/projectile/P)
	if(P.original == src)
		return TRUE
	else
		return FALSE

/obj/structure/mortar/attack_alien(mob/living/carbon/xenomorph/xeno)
	if(islarva(xeno))
		return XENO_NO_DELAY_ACTION

	if(fixed)
		to_chat(xeno, SPAN_XENOWARNING("The [src]'s supports are bolted and welded into the floor. It looks like it's going to be staying there."))
		return XENO_NO_DELAY_ACTION

	if(firing)
		xeno.animation_attack_on(src)
		xeno.flick_attack_overlay(src, "slash")
		playsound(src, "acid_hit", 25, 1)
		playsound(xeno, "alien_help", 25, 1)
		xeno.apply_damage(10, BURN)
		xeno.visible_message(SPAN_DANGER("[xeno] tried to knock the steaming hot [src] over, but burned itself and pulled away!"),
		SPAN_XENOWARNING("The [src] is burning hot! Wait a few seconds."))
		return XENO_ATTACK_ACTION

	xeno.visible_message(SPAN_DANGER("[xeno] lashes at the [src] and knocks it over!"),
	SPAN_DANGER("You knock the [src] over!"))
	xeno.animation_attack_on(src)
	xeno.flick_attack_overlay(src, "slash")
	playsound(loc, 'sound/effects/metalhit.ogg', 25)
	var/obj/item/mortar_kit/MK = new /obj/item/mortar_kit(loc)
	MK.name = name
	qdel(src)

	return XENO_ATTACK_ACTION

/obj/structure/mortar/attack_hand(mob/user)
	if(isyautja(user))
		to_chat(user, SPAN_WARNING("You kick [src] but nothing happens."))
		return
	if(!skillcheck(user, SKILL_ENGINEER, SKILL_ENGINEER_NOVICE))
		to_chat(user, SPAN_WARNING("You don't have the training to use [src]."))
		return
	if(busy)
		to_chat(user, SPAN_WARNING("Someone else is currently using [src]."))
		return
	if(firing)
		to_chat(user, SPAN_WARNING("[src]'s barrel is still steaming hot. Wait a few seconds and stop firing it."))
		return
	add_fingerprint(user)

	if(computer_enabled)
		if(lase_mode)
			internal_camera.tgui_interact(user)
		else
			tgui_interact(user)
	else
		if(!lase_mode)
			var/choice = tgui_alert(user, "Would you like to set the mortar's target coordinates, or dial the mortar? Setting coordinates will make you lose your fire adjustment.", "Mortar Dialing", list("Target", "Dial", "Cancel"))
			if(choice == "Cancel")
				return
			if(choice == "Target")
				handle_target(user, manual = TRUE)
			if(choice == "Dial")
				handle_dial(user, manual = TRUE)

/obj/structure/mortar/clicked(mob/user, list/mods)
	. = ..()
	if(mods["alt"] && user.Adjacent(src))
		if(skillcheck(user, SKILL_ENGINEER, SKILL_ENGINEER_NOVICE))
			toggle_lase_mode(user)

/obj/structure/mortar/proc/toggle_lase_mode(mob/user)
	lase_mode = !lase_mode
	if(lase_mode)
		to_chat(user, SPAN_NOTICE("You toggle the [src] to laser targeting mode."))
		reset_dials()
		if(linked_designator)
			RegisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE, PROC_REF(retrieve_laser_target))
			RegisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE_OFF, PROC_REF(lost_laser_target))
	else
		to_chat(user, SPAN_NOTICE("You toggle the [src] to coordinate targeting mode."))
		if(aimed || aiming)
			lost_laser_target()
		if(linked_designator)
			UnregisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE)
			UnregisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE_OFF)
		reset_dials()
	playsound(src, "sound/machines/click.ogg", 15, 1)

/obj/structure/mortar/proc/unlink_designator()
	set name = "Unlink Designator"
	set desc = "Unlinks a linked designator."
	set category = "Object"
	set src in oview(1)

	aiming = FALSE
	aimed = FALSE
	UnregisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE)
	UnregisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE_OFF)
	linked_designator = null
	verbs -= /obj/structure/mortar/proc/unlink_designator
	balloon_alert(usr, "unlinked")

/obj/structure/mortar/proc/reset_dials()
	dial_x = 0
	dial_y = 0
	targ_x = deobfuscate_x(0)
	targ_y = deobfuscate_y(0)

/obj/structure/mortar/get_examine_text(mob/user)
	. = ..()
	if(linked_designator)
		. += SPAN_NOTICE("It's currently linked to a laser designator with the [linked_designator.serial_number] serial number.")
	if(lase_mode)
		. += SPAN_NOTICE("It's in laser targeting mode.")
		if(aimed)
			. += SPAN_NOTICE("It's aimed on target and ready to fire!")
	else
		. += SPAN_NOTICE("It's in coordinate targeting mode.")

/obj/structure/mortar/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Mortar", "Mortar Interface")
		ui.open()

/obj/structure/mortar/ui_data(mob/user)
	return list(
		"data_target_x" = obfuscate_x(targ_x),
		"data_target_y" = obfuscate_y(targ_y),
		"data_target_z" = obfuscate_z(targ_z),
		"data_dial_x" = dial_x,
		"data_dial_y" = dial_y
	)

/obj/structure/mortar/ui_act(action, params)
	. = ..()
	if(.)
		return

	var/mob/user = usr
	if(get_dist(user, src) > 1)
		return FALSE

	switch(action)
		if("set_target")
			handle_target(user, text2num(params["target_x"]),  text2num(params["target_y"]), text2num(params["target_z"]))
			return TRUE

		if("set_offset")
			handle_dial(user, text2num(params["dial_x"]), text2num(params["dial_y"]))
			return TRUE

		if("operate_cam")
			internal_camera.tgui_interact(user)

/obj/structure/mortar/proc/handle_target(mob/user, temp_targ_x = 0, temp_targ_y = 0, temp_targ_z = 0, manual = FALSE)
	if(lase_mode)
		user.visible_message(SPAN_WARNING("The [src] is set to laser targeting mode, switch to coordinate targeting in order to dial coordinates!"))
		return
	if(manual)
		temp_targ_x = tgui_input_real_number(user, "Input the longitude of the target.")
		temp_targ_y = tgui_input_real_number(user, "Input the latitude of the target.")
		temp_targ_z = tgui_input_real_number(user, "Input the height of the target.")

	if(!can_fire_at(user, test_targ_x = deobfuscate_x(temp_targ_x), test_targ_y = deobfuscate_y(temp_targ_y), test_targ_z = deobfuscate_z(temp_targ_z)))
		return

	user.visible_message(SPAN_NOTICE("[user] starts adjusting [src]'s firing angle and distance."),
	SPAN_NOTICE("You start adjusting [src]'s firing angle and distance to match the new coordinates."))
	busy = TRUE

	var/soundfile = 'sound/machines/scanning.ogg'
	if(manual)
		soundfile = 'sound/items/Ratchet.ogg'
	playsound(loc, soundfile, 25, 1)

	var/success = do_after(user, 3 SECONDS, INTERRUPT_NO_NEEDHAND, BUSY_ICON_FRIENDLY)
	busy = FALSE
	if(!success)
		return
	user.visible_message(SPAN_NOTICE("[user] finishes adjusting [src]'s firing angle and distance."),
	SPAN_NOTICE("You finish adjusting [src]'s firing angle and distance to match the new coordinates."))
	targ_x = deobfuscate_x(temp_targ_x)
	targ_y = deobfuscate_y(temp_targ_y)
	targ_z = deobfuscate_z(temp_targ_z)
	var/offset_x_max = floor(abs((targ_x) - x)/offset_per_turfs) //Offset of mortar shot, grows by 1 every 20 tiles travelled
	var/offset_y_max = floor(abs((targ_y) - y)/offset_per_turfs)
	offset_x = rand(-offset_x_max, offset_x_max)
	offset_y = rand(-offset_y_max, offset_y_max)

	SStgui.update_uis(src)

/obj/structure/mortar/proc/retrieve_laser_target()
	SIGNAL_HANDLER
	if(!lase_mode)
		return
	visible_message(SPAN_NOTICE("[icon2html(src, viewers(src))] The [src] has detected a target and beings calibrating..."))
	aiming = TRUE
	aimed = FALSE
	playsound(loc, "sound/machines/scanning.ogg", 25, 1)
	addtimer(CALLBACK(src, PROC_REF(set_laser_target)), 1.5 SECONDS)
	busy_image_aim = image('icons/mob/do_afters.dmi', src, "busy_generic")
	busy_image_aim.flick_overlay(src, 1.5 SECONDS)

/obj/structure/mortar/proc/lost_laser_target()
	SIGNAL_HANDLER
	if(!lase_mode)
		return
	visible_message(SPAN_NOTICE("[icon2html(src, viewers(src))] The [src] has lost the laser target and returns to it's normal position."))
	aiming = FALSE
	aimed = FALSE
	playsound(loc, "sound/machines/scanning.ogg", 25, 1)
	busy_image_aim = image('icons/mob/do_afters.dmi', src, "busy_build")
	busy_image_aim.flick_overlay(src, 1 SECONDS)

/obj/structure/mortar/proc/set_laser_target()
	if(!aiming) // If lase went down before mortar has aimed, we cancel
		return
	var/obj/effect/overlay/temp/laser_target = linked_designator.laser
	if(!can_fire_at(null, laser_target.x, laser_target.y, laser_target.z, 0, 0))
		aiming = FALSE
		aimed = FALSE
		return
	visible_message(SPAN_NOTICE("[icon2html(src, viewers(src))] The [src] is ready to fire!"))
	aiming = FALSE
	aimed = TRUE

/obj/structure/mortar/proc/handle_dial(mob/user, temp_dial_x = 0, temp_dial_y = 0, manual = FALSE)
	if(lase_mode)
		user.visible_message(SPAN_WARNING("The [src] is set to laser targeting mode, switch to coordinate targeting in order to dial coordinates!"))
		return
	if(manual)
		temp_dial_x = tgui_input_number(user, "Set longitude adjustement from -10 to 10.", "Longitude", 0, 10, -10)
		temp_dial_y = tgui_input_number(user, "Set latitude adjustement from -10 to 10.", "Latitude", 0, 10, -10)

	if(!can_fire_at(user, test_dial_x = temp_dial_x, test_dial_y = temp_dial_y))
		return

	user.visible_message(SPAN_NOTICE("[user] starts dialing [src]'s firing angle and distance."),
	SPAN_NOTICE("You start dialing [src]'s firing angle and distance to match the new coordinates."))
	busy = TRUE

	var/soundfile = 'sound/machines/scanning.ogg'
	if(manual)
		soundfile = 'sound/items/Ratchet.ogg'
	playsound(loc, soundfile, 25, 1)

	var/success = do_after(user, 1.5 SECONDS, INTERRUPT_NO_NEEDHAND, BUSY_ICON_FRIENDLY)
	busy = FALSE
	if(!success)
		return
	user.visible_message(SPAN_NOTICE("[user] finishes dialing [src]'s firing angle and distance."),
	SPAN_NOTICE("You finish dialing [src]'s firing angle and distance to match the new coordinates."))
	dial_x = temp_dial_x
	dial_y = temp_dial_y

	SStgui.update_uis(src)

/obj/structure/mortar/attackby(obj/item/item, mob/user)
	if(istype(item, /obj/item/device/binoculars/range/designator))
		if(!skillcheck(user, SKILL_JTAC, SKILL_JTAC_TRAINED))
			to_chat(user, SPAN_WARNING("You don't know how to link your laser designator to the [src]."))
			return
		if(!lase_mode)
			to_chat(user, SPAN_WARNING("You need to switch the [src] to laser targeting before linking your laser designator!"))
			return
		if(aimed)
			to_chat(user, SPAN_WARNING("The [src] is currently targeting something!"))
			return
		to_chat(user, SPAN_NOTICE("You begin linking your laser designator to the [src].."))
		if(do_after(user, 2 SECONDS, INTERRUPT_ALL, BUSY_ICON_FRIENDLY))
			if(linked_designator) // Unregister the previous laser designator signal, if switching linked laser designator
				UnregisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE)
				UnregisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE_OFF)
			linked_designator = item
			RegisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE, PROC_REF(retrieve_laser_target))
			RegisterSignal(linked_designator, COMSIG_DESIGNATOR_LASE_OFF, PROC_REF(lost_laser_target))
			verbs += /obj/structure/mortar/proc/unlink_designator
			balloon_alert(user, "linked")
		return

	if(istype(item, /obj/item/mortar_shell))
		var/obj/item/mortar_shell/mortar_shell = item
		var/turf/target_turf = locate(targ_x + dial_x + offset_x, targ_y + dial_y + offset_y, targ_z)
		if(lase_mode)
			if(!linked_designator)
				to_chat(user, SPAN_WARNING("The [src] is in laser targeting mode, but there is no laser designator linked!"))
				return
			if(!aimed)
				to_chat(user, SPAN_WARNING("Cannot find valid laser target!"))
				return
			if(aiming)
				to_chat(user, SPAN_WARNING("The [src] is still calibrating!"))
			else
				target_turf = get_turf(linked_designator.laser)
		var/area/target_area = get_area(target_turf)
		if(!skillcheck(user, SKILL_ENGINEER, SKILL_ENGINEER_NOVICE))
			to_chat(user, SPAN_WARNING("You don't have the training to fire [src]."))
			return
		if(busy)
			to_chat(user, SPAN_WARNING("Someone else is currently using [src]."))
			return
		if(!ship_side)
			if(targ_x == 0 && targ_y == 0 && targ_z == 0 && !lase_mode) //Mortar wasn't set
				to_chat(user, SPAN_WARNING("[src] needs to be aimed first."))
				return
			if(!target_turf)
				to_chat(user, SPAN_WARNING("You cannot fire [src] to this target."))
				return
			if(!istype(target_area))
				to_chat(user, SPAN_WARNING("This area is out of bounds!"))
				return
			if(CEILING_IS_PROTECTED(target_area.ceiling, CEILING_PROTECTION_TIER_2) || protected_by_pylon(TURF_PROTECTION_MORTAR, target_turf))
				to_chat(user, SPAN_WARNING("You cannot hit the target. It is probably underground."))
				return
			if(MODE_HAS_MODIFIER(/datum/gamemode_modifier/lz_mortar_protection) && target_area.is_landing_zone)
				to_chat(user, SPAN_WARNING("You cannot bomb the landing zone!"))
				return

		if(ship_side)
			var/crash_occurred = (SSticker?.mode?.is_in_endgame)
			if(crash_occurred)
				var/turf/our_turf = get_turf(src)
				target_turf = our_turf
				travel_time = 0.5 SECONDS
			else
				to_chat(user, SPAN_RED("You realize how bad of an idea this is and quickly stop."))
				return
		else
			var/turf/deviation_turf = locate(target_turf.x + pick(-1,0,0,1), target_turf.y + pick(-1,0,0,1), target_turf.z) //Small amount of spread so that consecutive mortar shells don't all land on the same tile
			if(deviation_turf && !lase_mode) // Mortar is accurate in lase mode
				target_turf = deviation_turf

		user.visible_message(SPAN_NOTICE("[user] starts loading \a [mortar_shell.name] into [src]."),
		SPAN_NOTICE("You start loading \a [mortar_shell.name] into [src]."))
		playsound(loc, 'sound/weapons/gun_mortar_reload.ogg', 50, 1)
		busy = TRUE
		var/success = do_after(user, 1.5 SECONDS, INTERRUPT_NO_NEEDHAND, BUSY_ICON_HOSTILE)
		busy = FALSE
		if(success)
			user.visible_message(SPAN_NOTICE("[user] loads \a [mortar_shell.name] into [src]."),
			SPAN_NOTICE("You load \a [mortar_shell.name] into [src]."))
			visible_message("[icon2html(src, viewers(src))] [SPAN_DANGER("The [name] fires!")]")
			user.drop_inv_item_to_loc(mortar_shell, src)
			playsound(loc, 'sound/weapons/gun_mortar_fire.ogg', 50, 1)
			busy = FALSE
			firing = TRUE
			flick(icon_state + "_fire", src)
			mortar_shell.cause_data = create_cause_data(initial(mortar_shell.name), user, src)
			mortar_shell.forceMove(src)

			var/turf/mortar_turf = get_turf(src)
			mortar_turf.ceiling_debris_check(2)

			for(var/mob/mob in range(7))
				shake_camera(mob, 3, 1)

			addtimer(CALLBACK(src, PROC_REF(handle_shell), target_turf, mortar_shell), travel_time)

	if(HAS_TRAIT(item, TRAIT_TOOL_WRENCH))
		if(!skillcheck(user, SKILL_ENGINEER, SKILL_ENGINEER_NOVICE))
			to_chat(user, SPAN_WARNING("You don't have the training to undeploy [src]."))
			return
		if(fixed)
			to_chat(user, SPAN_WARNING("[src]'s supports are bolted and welded into the floor. It looks like it's going to be staying there."))
			return
		if(busy)
			to_chat(user, SPAN_WARNING("Someone else is currently using [src]."))
			return
		if(firing)
			to_chat(user, SPAN_WARNING("[src]'s barrel is still steaming hot. Wait a few seconds and stop firing it."))
			return
		playsound(loc, 'sound/items/Ratchet.ogg', 25, 1)
		user.visible_message(SPAN_NOTICE("[user] starts undeploying [src]."),
				SPAN_NOTICE("You start undeploying [src]."))
		if(do_after(user, 4 SECONDS, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD))
			user.visible_message(SPAN_NOTICE("[user] undeploys [src]."),
				SPAN_NOTICE("You undeploy [src]."))
			playsound(loc, 'sound/items/Deconstruct.ogg', 25, 1)
			var/obj/item/mortar_kit/mortar = new /obj/item/mortar_kit(loc)
			if(linked_designator)
				mortar.linked_designator = linked_designator
			mortar.name = src.name
			qdel(src)

	if(HAS_TRAIT(item, TRAIT_TOOL_SCREWDRIVER))
		if(do_after(user, 1 SECONDS, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD))
			user.visible_message(SPAN_NOTICE("[user] toggles the targeting computer on [src]."),
				SPAN_NOTICE("You toggle the targeting computer on [src]."))
			computer_enabled = !computer_enabled
			playsound(loc, 'sound/machines/switch.ogg', 25, 1)

/obj/structure/mortar/ex_act(severity)
	switch(severity)
		if(EXPLOSION_THRESHOLD_MEDIUM to INFINITY)
			qdel(src)

/obj/effect/mortar_effect
	icon = 'icons/obj/structures/mortar.dmi'
	icon_state = "mortar_ammo_custom"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	invisibility = INVISIBILITY_MAXIMUM

/obj/structure/mortar/proc/handle_shell(turf/target, obj/item/mortar_shell/shell)
	if(protected_by_pylon(TURF_PROTECTION_MORTAR, target))
		firing = FALSE
		return

	if(ship_side)
		var/turf/our_turf = get_turf(src)
		shell.detonate(our_turf)
		return

	if(istype(shell, /obj/item/mortar_shell/custom)) // big shell warning for ghosts
		var/obj/effect/effect = new /obj/effect/mortar_effect(target)
		QDEL_IN(effect, 5 SECONDS)
		notify_ghosts(header = "Custom Shell", message = "A custom mortar shell is about to land at [get_area(target)].", source = effect)

	playsound(target, 'sound/weapons/gun_mortar_travel.ogg', 50, 1)
	var/relative_dir
	for(var/mob/mob in range(15, target))
		if(get_turf(mob) == target)
			relative_dir = 0
		else
			relative_dir = Get_Compass_Dir(mob, target)
		mob.show_message( \
			SPAN_DANGER("СНАРЯД ПАДАЕТ [SPAN_UNDERLINE(relative_dir ? uppertext(("НА " + dir2text_ru(relative_dir, PREPOSITIONAL) + " ОТ ВАС")) : uppertext("ПРЯМО НА ВАС"))]!"), SHOW_MESSAGE_VISIBLE, \
			SPAN_DANGER("ВЫ СЛЫШИТЕ, КАК ЧТО-ТО ПАДАЕТ [SPAN_UNDERLINE(relative_dir ? uppertext(("НА " + dir2text_ru(relative_dir, PREPOSITIONAL))) : uppertext("ПРЯМО НА ВАС"))]!"), SHOW_MESSAGE_AUDIBLE \
		)
	sleep(2.5 SECONDS) // Sleep a bit to give a message
	for(var/mob/mob in range(10, target))
		if(get_turf(mob) == target)
			relative_dir = 0
		else
			relative_dir = Get_Compass_Dir(mob, target)
		mob.show_message( \
			SPAN_HIGHDANGER("СНАРЯД ВОТ-ВОТ УПАДЁТ [SPAN_UNDERLINE(relative_dir ? uppertext(("НА " + dir2text_ru(relative_dir, PREPOSITIONAL) + " ОТ ВАС")) : uppertext("ПРЯМО НА ВАС"))]!"), SHOW_MESSAGE_VISIBLE, \
			SPAN_HIGHDANGER("ВЫ СЛЫШИТЕ, КАК ЧТО-ТО ВОТ-ВОТ УПАДЁТ [SPAN_UNDERLINE(relative_dir ? uppertext(("НА " + dir2text_ru(relative_dir, PREPOSITIONAL) + " ОТ ВАС")) : uppertext("ПРЯМО НА ВАС"))]!"), SHOW_MESSAGE_AUDIBLE \
		)
	if(MODE_HAS_MODIFIER(/datum/gamemode_modifier/mortar_laser_warning))
		new /obj/effect/overlay/temp/blinking_laser(target)
	sleep(2 SECONDS) // Wait out the rest of the landing time
	target.ceiling_debris_check(2)
	if(!protected_by_pylon(TURF_PROTECTION_MORTAR, target))
		shell.detonate(target)
	qdel(shell)
	firing = FALSE

/obj/structure/mortar/proc/can_fire_at(mob/user = null, test_targ_x = targ_x, test_targ_y = targ_y, test_targ_z = targ_z, test_dial_x, test_dial_y)
	var/dialing = test_dial_x || test_dial_y
	var/attempt_info
	var/can_fire = TRUE
	if(ship_side)
		attempt_info = SPAN_WARNING(("[user ? "You" : "The [src]"] cannot aim the mortar while on a ship."))
		can_fire = FALSE
	if(test_dial_x + test_targ_x > world.maxx || test_dial_x + test_targ_x < 0)
		attempt_info = SPAN_WARNING("[user ? "You" : "The [src]"] cannot [dialing ? "dial to" : "aim at"] this [lase_mode ? "target" : "coordinate"], it is outside of the area of operations.")
		can_fire = FALSE
	if(test_dial_x < -10 || test_dial_x > 10 || test_dial_y < -10 || test_dial_y > 10)
		attempt_info = SPAN_WARNING("[user ? "You" : "The [src]"] cannot [dialing ? "dial to" : "aim at"] this [lase_mode ? "target" : "coordinate"], it is too far away from the original target.")
		can_fire = FALSE
	if(test_dial_y + test_targ_y > world.maxy || test_dial_y + test_targ_y < 0)
		attempt_info = SPAN_WARNING("[user ? "You" : "The [src]"] cannot [dialing ? "dial to" : "aim at"] this [lase_mode ? "target" : "coordinate"], it is outside of the area of operations.")
		can_fire = FALSE
	if(get_dist(src, locate(test_targ_x + test_dial_x, test_targ_y + test_dial_y, z)) < min_range)
		attempt_info = SPAN_WARNING("[user ? "You" : "The [src]"] cannot [dialing ? "dial to" : "aim at"] this [lase_mode ? "target" : "coordinate"], it is too close to [user ? "your" : "the"] mortar.")
		can_fire = FALSE
	if(!is_ground_level(test_targ_z))
		attempt_info = SPAN_WARNING("[user ? "You" : "The [src]"] cannot [dialing ? "dial to" : "aim at"] this [lase_mode ? "target" : "coordinate"], it is outside of the area of operations.")
		can_fire = FALSE
	if(get_dist(src, locate(test_targ_x + test_dial_x, test_targ_y + test_dial_y, z)) > max_range)
		attempt_info = SPAN_WARNING("[user ? "You" : "The [src]"] cannot [dialing ? "dial to" : "aim at"] this [lase_mode ? "target" : "coordinate"], it is too far from [user ? "your" : "the"] mortar.")
		can_fire = FALSE
	if(busy)
		attempt_info = SPAN_WARNING("Someone else is currently using this mortar.")
		can_fire = FALSE

	if(!can_fire)
		if(user)
			to_chat(user, attempt_info)
		else
			visible_message(attempt_info)
	return can_fire

/obj/structure/mortar/fixed
	desc = "A manual, crew-operated mortar system intended to rain down 80mm goodness on anything it's aimed at. Uses manual targeting dials. Insert round to fire. This one is bolted and welded into the ground."
	fixed = TRUE

/obj/structure/mortar/wo
	fixed = TRUE
	offset_per_turfs = 50 // The mortar is located at the edge of the map in WO, This to to prevent mass FF
	max_range = 999

//The portable mortar item
/obj/item/mortar_kit
	name = "\improper M402 mortar portable kit"
	desc = "A manual, crew-operated mortar system intended to rain down 80mm goodness on anything it's aimed at. Needs to be set down first"
	icon = 'icons/obj/structures/mortar.dmi'
	icon_state = "mortar_m402_carry"
	item_state = "mortar_m402_carry"
	item_icons = list(
		WEAR_L_HAND = 'icons/mob/humans/onmob/inhands/items_by_map/jungle_lefthand.dmi',
		WEAR_R_HAND = 'icons/mob/humans/onmob/inhands/items_by_map/jungle_righthand.dmi'
	)
	unacidable = TRUE
	w_class = SIZE_HUGE //No dumping this in a backpack. Carry it, fatso
	flags_atom = FPRINT|CONDUCT|MAP_COLOR_INDEX
	/// Linked designator, keeping track of it on undeploy so we don't have to relink it everytime.
	var/obj/item/device/binoculars/range/designator/linked_designator

/obj/item/mortar_kit/Initialize(...)
	. = ..()
	select_gamemode_skin(type)

/obj/item/mortar_kit/ex_act(severity)
	switch(severity)
		if(EXPLOSION_THRESHOLD_MEDIUM to INFINITY)
			deconstruct(FALSE)

/obj/item/mortar_kit/attack_self(mob/user)
	..()
	var/turf/deploy_turf = get_turf(user)
	if(!deploy_turf)
		return
	if(!skillcheck(user, SKILL_ENGINEER, SKILL_ENGINEER_NOVICE))
		to_chat(user, SPAN_WARNING("You don't have the training to deploy [src]."))
		return
	var/area/area = get_area(deploy_turf)
	if(CEILING_IS_PROTECTED(area.ceiling, CEILING_PROTECTION_TIER_1) && is_ground_level(deploy_turf.z))
		to_chat(user, SPAN_WARNING("You probably shouldn't deploy [src] indoors."))
		return
	user.visible_message(SPAN_NOTICE("[user] starts deploying [src]."),
		SPAN_NOTICE("You start deploying [src]."))
	playsound(deploy_turf, 'sound/items/Deconstruct.ogg', 25, 1)
	if(do_after(user, 4 SECONDS, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD))
		var/obj/structure/mortar/mortar = new /obj/structure/mortar(deploy_turf)
		if(linked_designator)
			mortar.linked_designator = linked_designator
		if(!is_ground_level(deploy_turf.z))
			mortar.ship_side = TRUE
			user.visible_message(SPAN_NOTICE("[user] deploys [src]."),
				SPAN_NOTICE("You deploy [src]. This is a bad idea."))
		else
			user.visible_message(SPAN_NOTICE("[user] deploys [src]."),
				SPAN_NOTICE("You deploy [src]."))
		playsound(deploy_turf, 'sound/weapons/gun_mortar_unpack.ogg', 25, 1)
		mortar.name = src.name
		mortar.setDir(user.dir)
		qdel(src)
