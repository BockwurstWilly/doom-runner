// Title scene (TITLEMAP) and the main menu class

// decorative actor for the title scene; kind selects sprite set
class RTitleProp : Actor
{
	int kind;          // 0 marine, 1 hero, 2 imp, 3 zombie, 4 baron, 5 cyber, 6 barrel, 7 gate good, 8 gate bad
	double walk;       // approach speed (towards the camera, -y)
	double startY, dieY;
	bool dying;
	int timer;

	Default
	{
		+NOINTERACTION
		+NOBLOCKMAP
		RenderStyle "Translucent";
		Alpha 1.0;
	}

	States
	{
	Spawn:
		TNT1 A -1;
		stop;
	Marine:
		PLAY ABCD 5;
		loop;
	Imp:
		TROO ABCD 6;
		loop;
	ImpDie:
		TROO I 6;
		TROO J 6;
		TROO K 6;
		TROO L 6;
		TROO M -1;
		stop;
	Zombie:
		POSS ABCD 6;
		loop;
	ZombieDie:
		POSS H 6;
		POSS I 6;
		POSS J 6;
		POSS K 6;
		POSS L -1;
		stop;
	Baron:
		BOSS ABCD 8;
		loop;
	Cyber:
		CYBR ABCD 9;
		loop;
	Barrel:
		BAR1 AB 8;
		loop;
	GateGood:
		RGAT A -1;
		stop;
	GateBad:
		RGAT B -1;
		stop;
	}

	void Setup(int k, double spd = 0)
	{
		kind = k;
		walk = spd;
		startY = pos.y;
		Angle = k <= 1 ? 90 : 270;
		switch (k)
		{
		case 0: case 1: SetStateLabel("Marine"); break;
		case 2: SetStateLabel("Imp"); break;
		case 3: SetStateLabel("Zombie"); break;
		case 4: SetStateLabel("Baron"); break;
		case 5: SetStateLabel("Cyber"); break;
		case 6: SetStateLabel("Barrel"); break;
		case 7: SetStateLabel("GateGood"); break;
		default: SetStateLabel("GateBad"); break;
		}
		if (k == 0) A_SetTranslation('RunnerAllyBlue');
		if (k >= 7) { Scale = (1.1, 0.85); bBRIGHT = true; }
		if (k == 4 || k == 5) Scale = (1.0, 1.0);
	}

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed || walk == 0) return;
		if (!dying)
		{
			SetOrigin(pos - (0, walk, 0), true);
			if (Alpha < 1) Alpha = min(1.0, Alpha + 0.02);
			if (pos.y < dieY)
			{
				dying = true;
				timer = 110;
				if (kind == 2) SetStateLabel("ImpDie");
				else SetStateLabel("ZombieDie");
			}
			return;
		}
		if (--timer < 30) Alpha = max(0.0, Alpha - 0.035);
		if (timer <= 0)
		{
			dying = false;
			Alpha = 0;
			SetOrigin((pos.x, startY + FRandom(0, 60), pos.z), false);
			if (kind == 2) SetStateLabel("Imp");
			else SetStateLabel("Zombie");
		}
	}
}

// main menu: drops the Brutal Doom options entry when Brutal Doom is not loaded
class RunnerMainMenu : ListMenu
{
	mixin RunnerMenuCursor;

	// system cursors are capped at 32x32 by GZDoom, so our menus hide it and draw a
	// software cursor scaled to the screen instead (cvars may only change during menu input)
	static void SetOSCursor(bool hidden)
	{
		String want = hidden ? "RCURSX" : "None";
		let c = CVar.FindCVar('vid_cursor');
		if (c && c.GetString() != want) c.SetString(want);
		// Brutal Doom's gameplay tips at the top of the screen don't fit Doom Runner
		let tips = CVar.FindCVar('bd_Tips');
		if (tips && tips.GetInt() != 0) tips.SetInt(0);
	}

	override void Drawer()
	{
		Super.Drawer();
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double sc = max(1.0, sh / 540.0);
		bool bd = MenuDescriptor.GetDescriptor('BrutalMenu') != null;
		String s = StringTable.Localize(bd ? "$RR_MM_BD" : "$RR_MM_NOBD");
		Font f = NewSmallFont;
		double x = (sw - f.StringWidth(s) * sc) / 2;
		double y = sh * 0.9;
		Screen.DrawText(f, Font.CR_BLACK, x + sc, y + sc, s, DTA_ScaleX, sc, DTA_ScaleY, sc);
		Screen.DrawText(f, bd ? Font.CR_GREEN : Font.CR_GOLD, x, y, s, DTA_ScaleX, sc, DTA_ScaleY, sc);
		RunnerMainMenu.DrawCredit();
		DrawSoftCursor();
	}

	// author credit, bottom right (main menu and title screen)
	static ui void DrawCredit()
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double sc = max(1.0, sh / 720.0);
		String s = StringTable.Localize("$RR_CREDIT");
		Font f = NewSmallFont;
		double x = sw - f.StringWidth(s) * sc - 12 * sc;
		double y = sh - f.GetHeight() * sc - 8 * sc;
		Screen.DrawText(f, Font.CR_BLACK, x + sc, y + sc, s, DTA_ScaleX, sc, DTA_ScaleY, sc);
		Screen.DrawText(f, Font.CR_GRAY, x, y, s, DTA_ScaleX, sc, DTA_ScaleY, sc);
	}

	override void Init(Menu parent, ListMenuDescriptor desc)
	{
		if (!MenuDescriptor.GetDescriptor('BrutalMenu'))
		{
			for (int i = 0; i < desc.mItems.Size(); i++)
			{
				int param;
				Name act;
				[act, param] = desc.mItems[i].GetAction();
				if (act != 'BrutalMenu') continue;
				for (int j = i + 1; j < desc.mItems.Size(); j++)
				{
					if (desc.mItems[j].Selectable()) desc.mItems[j].OffsetPositionY(-desc.mLinespacing);
				}
				desc.mItems.Delete(i);
				if (desc.mSelectedItem >= desc.mItems.Size() || !desc.mItems[desc.mSelectedItem].Selectable())
					desc.mSelectedItem = -1;
				break;
			}
		}
		// Freedoom: menu items in our own font
		Font hf = RunnerHandler.HudFont();
		for (int i = 0; i < desc.mItems.Size(); i++)
		{
			let ti = ListMenuItemTextItem(desc.mItems[i]);
			if (ti) ti.mFont = hf;
		}
		Super.Init(parent, desc);
	}

	override bool OnUIEvent(UIEvent ev)
	{
		CursorEvent(ev);
		bool res = Super.OnUIEvent(ev);
		CursorAfter();
		return res;
	}

	override bool MenuEvent(int mkey, bool fromcontroller)
	{
		bool res = Super.MenuEvent(mkey, fromcontroller);
		CursorAfter();
		return res;
	}
}

extend class RunnerHandler
{
	Array<RTitleProp> titleMarines;
	Array<RTitleProp> titleFoes;

	RTitleProp TitleProp(int k, double x, double y, double spd = 0)
	{
		let p = RTitleProp(Actor.Spawn("RTitleProp", (x, y, 0)));
		p.Setup(k, spd);
		return p;
	}

	void BuildTitle()
	{
		let pm = players[consoleplayer].mo;
		if (pm) pm.A_SetRenderStyle(0, STYLE_None);
		for (double ty = -1000; ty < 4000; ty += 280)
		{
			Actor.Spawn("RTorch", (-162, ty, 0));
			Actor.Spawn("RTorch", (162, ty, 0));
		}
		// the squad, seen from behind
		titleMarines.Push(TitleProp(1, 0, 40));
		titleMarines.Push(TitleProp(0, -48, 6));
		titleMarines.Push(TitleProp(0, 48, 6));
		titleMarines.Push(TitleProp(0, -96, -30));
		titleMarines.Push(TitleProp(0, 96, -30));
		// gates
		TitleProp(7, -76, 470);
		TitleProp(8, 76, 470);
		TitleProp(6, -126, 190);
		TitleProp(6, 124, 300);
		// an imp pack and a zombie pack walking in, a baron and the cyberdemon behind them
		for (int i = 0; i < 5; i++)
		{
			let p = TitleProp(2, -100 + i * 50 + FRandom(-8, 8), 300 + i * 37 % 60, 0.45);
			p.dieY = 140;
			titleFoes.Push(p);
		}
		for (int i = 0; i < 6; i++)
		{
			let p = TitleProp(3, -110 + i * 44, 420 + i * 53 % 80, 0.45);
			p.dieY = 140;
			titleFoes.Push(p);
		}
		TitleProp(4, -96, 560);
		TitleProp(5, 80, 660);
		cam = RunnerCam(Actor.Spawn("RunnerCam", (0, -230, 235)));
		cam.SetView(1, 0, 25);
		cam.Pitch = 25;
		cam.Angle = 90;
	}

	void TitleTick()
	{
		if (!cam) return;
		players[consoleplayer].camera = cam;
		phaseTime++;
		cam.SetOrigin((sin(phaseTime * 0.4) * 18, -230, 235 + sin(phaseTime * 0.9) * 3), true);
		// the squad fires at the closest living foe
		if (phaseTime % 4 == 0 && titleMarines.Size() > 0)
		{
			let m = titleMarines[Random(0, titleMarines.Size() - 1)];
			RTitleProp best;
			for (int i = 0; i < titleFoes.Size(); i++)
			{
				let f = titleFoes[i];
				if (f && !f.dying && f.Alpha > 0.5 && (!best || f.pos.y < best.pos.y)) best = f;
			}
			if (m && best)
			{
				Vector3 from = m.pos + (0, 12, 34);
				Vector3 d = best.pos + (FRandom(-6, 6), 0, 30) - from;
				let t = RTracerFX(Actor.Spawn("RTracerFX", from));
				if (t)
				{
					t.Vel = d.Unit() * 32;
					t.life = int(d.Length() / 32);
				}
				// a hit now and then speeds up the kill
				if (Random(0, 5) == 0) best.SetOrigin(best.pos - (0, 6, 0), true);
			}
		}
	}

	ui void DrawTitle(RenderEvent e)
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double u = HudScale();
		WorldTxt(e, HudFont(), Font.CR_WHITE, StringTable.Localize("$RR_G3"), (-76, 470, 64), 10);
		WorldTxt(e, HudFont(), Font.CR_WHITE, "+5", (-76, 470, 40), 19);
		WorldTxt(e, HudFont(), Font.CR_WHITE, StringTable.Localize("$RR_G0"), (76, 470, 64), 10);
		WorldTxt(e, HudFont(), Font.CR_WHITE, StringTable.Localize("$RR_LANGID") == "de" ? "-0,10" : "-0.10", (76, 470, 40), 19);
		Screen.Dim(Color(0, 0, 0), 0.45, 0, 0, sw, int(sh * 0.06));
		if (Menu.GetCurrentMenu())
		{
			Screen.Dim(Color(0, 0, 0), 0.4, 0, 0, sw, sh);
			return;
		}
		TextureID logo = TexMan.CheckForTexture("RLOGO", TexMan.Type_Any);
		if (logo.IsValid()) Screen.DrawTexture(logo, false, 60, 4, DTA_Clean, true);
		double a = 0.55 + 0.45 * sin(level.time * 6.0);
		Txt(HudFont(), Font.CR_GOLD, StringTable.Localize("$RR_PRESSKEY"), sw * 0.5, sh * 0.86, 3.2 * u, a);
		RunnerMainMenu.DrawCredit();
	}
}
