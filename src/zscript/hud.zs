// HUD / overlay drawing (UI scope)

extend class RunnerHandler
{
	// ----------------------------------------------------------- helpers
	ui String Dec(double v, int digits)
	{
		String s = digits == 2 ? String.Format("%.2f", v) : String.Format("%.1f", v);
		if (StringTable.Localize("$RR_LANGID") == "de") s.Replace(".", ",");
		return s;
	}

	// draw text; x is centre (or left edge), y is top. sc = pixel scale.
	ui void Txt(Font f, int col, String s, double x, double y, double sc, double alpha = 1.0, bool center = true, bool shadow = true)
	{
		if (sc <= 0) return;
		double tx = x;
		if (center) tx -= f.StringWidth(s) * sc * 0.5;
		if (shadow)
			Screen.DrawText(f, Font.CR_BLACK, tx + 1.5 * sc, y + 1.5 * sc, s,
				DTA_ScaleX, sc, DTA_ScaleY, sc, DTA_Alpha, alpha * 0.7);
		Screen.DrawText(f, col, tx, y, s, DTA_ScaleX, sc, DTA_ScaleY, sc, DTA_Alpha, alpha);
	}

	ui void Img(String name, double x, double y, double w, double h, double alpha = 1.0)
	{
		TextureID tex = TexMan.CheckForTexture(name, TexMan.Type_Any);
		if (!tex.IsValid()) return;
		Screen.DrawTexture(tex, false, x, y, DTA_DestWidthF, w, DTA_DestHeightF, h, DTA_Alpha, alpha);
	}

	// draw an IWAD sprite (or any texture) centred in a box, keeping aspect
	ui void Icon(String name, double cx, double cy, double maxW, double maxH, double alpha = 1.0)
	{
		TextureID tex = TexMan.CheckForTexture(name, TexMan.Type_Any);
		if (!tex.IsValid()) return;
		int tw, th;
		[tw, th] = TexMan.GetSize(tex);
		if (tw <= 0 || th <= 0) return;
		double k = min(maxW / tw, maxH / th);
		double w = tw * k, h = th * k;
		Screen.DrawTexture(tex, false, cx - w / 2, cy - h / 2, DTA_DestWidthF, w, DTA_DestHeightF, h,
			DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, alpha);
	}

	ui String SoulFrame()
	{
		static const String fr[] = { "SOULA0", "SOULB0", "SOULC0", "SOULD0" };
		return fr[(gametic / 6) % 4];
	}

	ui double Focal()
	{
		int vx, vy, vw, vh;
		[vx, vy, vw, vh] = Screen.GetViewWindow();
		// GZDoom keeps the vertical FOV of a 4:3 view on wide screens and the horizontal FOV on
		// narrow (portrait) screens; fov = the camera's FOV (90 normally, rr_camfov for videos)
		double fov = 90;
		let cam = players[consoleplayer].camera;
		if (cam && cam.CameraFOV > 0) fov = cam.CameraFOV;
		double ratio = min(double(vw) / max(vh, 1), 4.0 / 3.0);
		return vh * 0.5 * ratio / tan(fov * 0.5);
	}

	// world -> screen. z of result = depth (<= 0: behind camera)
	ui Vector3 Project(RenderEvent e, Vector3 p)
	{
		Vector3 d = p - e.ViewPos;
		double ca = cos(e.ViewAngle), sa = sin(e.ViewAngle);
		double cp = cos(e.ViewPitch), sp = sin(e.ViewPitch);
		double fh = d.x * ca + d.y * sa;
		double rt = d.x * sa - d.y * ca;
		double fw = fh * cp - d.z * sp;
		double up = (fh * sp + d.z * cp) * 1.2; // doom pixel aspect
		if (fw < 8) return (0, 0, -1);
		int vx, vy, vw, vh;
		[vx, vy, vw, vh] = Screen.GetViewWindow();
		double focal = Focal();
		return (vx + vw * 0.5 + rt / fw * focal, vy + vh * 0.5 - up / fw * focal, fw);
	}

	// text with a given world height, anchored at its vertical centre
	ui void WorldTxt(RenderEvent e, Font f, int col, String s, Vector3 p, double worldH, double alpha = 1.0, double maxSc = 99)
	{
		Vector3 sp = Project(e, p);
		if (sp.z <= 0 || sp.z > 3200) return;
		double sc = worldH * Focal() / sp.z / f.GetHeight();
		if (sc < 0.25) return;
		sc = min(sc, maxSc);
		Txt(f, col, s, sp.x, sp.y - f.GetHeight() * sc * 0.5, sc, alpha);
	}

	ui Vector3 IPos(Actor a, double frac)
	{
		return a.Prev + (a.Pos - a.Prev) * frac;
	}

	// ------------------------------------------------------------- overlay
	override void RenderOverlay(RenderEvent e)
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double u = HudScale();

		if (title) { DrawTitle(e); return; }
		DrawWorldLabels(e);

		if (hurtFlash > 0) Screen.Dim(Color(255, 255, 0, 0), hurtFlash * 0.016, 0, 0, sw, sh);

		DrawMoney(u);
		if (phase == 0) DrawMenu(u);
		else if (phase == 1) DrawRunHud(u);
		else DrawResult(u);
		if (phase != 1) DrawCursor(u);
	}

	ui void DrawWorldLabels(RenderEvent e)
	{
		let pm = players[consoleplayer].mo;
		double py = pm ? pm.pos.y : 0;
		for (int i = targets.Size() - 1; i >= 0; i--)
		{
			let t = targets[i];
			if (!t || t.pos.y < py - 10) continue;
			Vector3 p = IPos(t, e.FracTic);
			let g = RGate(t);
			if (g)
			{
				double a = g.Alpha;
				WorldTxt(e, HudFont(), Font.CR_WHITE, g.KindName(), p + (0, 0, 64), 10, a);
				WorldTxt(e, HudFont(), Font.CR_WHITE, g.ValueText(), p + (0, 0, 40), 19, a);
				continue;
			}
			if (t.dead) continue;
			if (t is "RBoss")
			{
				WorldTxt(e, HudFont(), Font.CR_WHITE, String.Format("%d", int(ceil(t.hp))), p + (0, 0, t.Height + 26), 24);
			}
			else if (t is "REnemy")
			{
				WorldTxt(e, HudFont(), Font.CR_WHITE, String.Format("%d", int(ceil(t.hp))), p + (0, 0, t.Height + 14), 13);
			}
			else
			{
				WorldTxt(e, HudFont(), Font.CR_WHITE, String.Format("%d", int(ceil(t.hp))), p + (0, 0, t is "RCrate" ? 22 : 16), 18);
			}
		}

		for (int i = 0; i < extras.Size(); i++)
		{
			let x = extras[i];
			if (!x || x.pos.y < py - 10) continue;
			Vector3 p = IPos(x, e.FracTic);
			if (x is "RRecruit")
			{
				WorldTxt(e, HudFont(), Font.CR_GREEN, "x1", p + (0, 8, 72), 10);
				WorldTxt(e, HudFont(), Font.CR_WHITE, StringTable.Localize("$RR_MARINE"), p + (0, 8, 60), 9);
			}
			else if (x is "RPickup")
			{
				WorldTxt(e, HudFont(), Font.CR_GOLD, RPickup(x).LabelText(), p + (0, 0, 52), 9);
			}
			else if (x is "RFinish")
			{
				WorldTxt(e, HudFont(), Font.CR_WHITE, StringTable.Localize("$RR_EXIT"), p + (0, 0, 168), 28);
			}
		}

		for (int i = 0; i < ftS.Size(); i++)
		{
			double a = clamp(ftT[i] / 20.0, 0.0, 1.0);
			Vector3 p = (ftX[i], ftY[i], ftZ[i]) + (0, 0, e.FracTic * 1.1);
			WorldTxt(e, HudFont(), ftCol[i], ftS[i], p, 15, a, Screen.GetHeight() / 1080.0 * 3.0);
		}
	}

	ui void DrawMoney(double u)
	{
		int sw = Screen.GetWidth();
		double x = sw - 360 * u;
		Img("RPILL", x, 34 * u, 320 * u, 80 * u);
		Icon(SoulFrame(), x + 10 * u, 74 * u, 92 * u, 92 * u);
		Txt(HudFont(), Font.CR_GOLD, String.Format("%d", money), x + 175 * u, 50 * u, 3.0 * u);
		if (phase == 1 && runCash > 0)
			Txt(HudFont(), Font.CR_GREEN, String.Format("+%d", runCash), x + 175 * u, 126 * u, 2.4 * u);
	}

	// big HUD font: Doom II's BigFont, or Doom Runner's own font on Freedoom (whose
	// stylised font draws 0 and O as diamonds - hard to read for numbers)
	static ui Font HudFont()
	{
		if (Wads.CheckNumForName("FREEDOOM", Wads.ns_global) < 0) return BigFont;
		Font f = Font.GetFont('RRBIG');
		return f ? f : BigFont;
	}

	// HUD unit: 1 = 1080p height; on narrow/portrait screens the width limits it
	ui double HudScale()
	{
		return min(Screen.GetHeight() / 1080.0, Screen.GetWidth() / 1250.0);
	}

	// ------------------------------------------------------------ mouse
	ui void MoveCursor(double dx, double dy)
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		if (!curInit) { curX = sw * 0.5; curY = sh * 0.6; curInit = true; }
		double k = 0.6 * sh / 1080.0;
		curX = clamp(curX + dx * k, 0, sw - 1);
		curY = clamp(curY - dy * k, 0, sh - 1);
	}

	ui void DrawCursor(double u)
	{
		if (!curInit) { curX = Screen.GetWidth() * 0.5; curY = Screen.GetHeight() * 0.6; curInit = true; }
		Img("RCURS3", curX, curY, 65 * u, 65 * u);
	}

	// layout shared by DrawMenu and the mouse: 0-2 = upgrade cards, 3 = PLAY button, -1 = nothing
	ui int MenuHit(double mx, double my)
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double u = HudScale();
		double cx = sw * 0.5;
		double bw = 400 * u, bh = 136 * u, by = sh * 0.47;
		if (abs(mx - cx) <= bw / 2 && abs(my - by) <= bh / 2) return 3;
		double cw = 240 * u, ch = 350 * u, gap = 26 * u;
		double x0 = cx - (cw * 3 + gap * 2) / 2;
		double y0 = sh * 0.655;
		for (int i = 0; i < 3; i++)
		{
			double x = x0 + i * (cw + gap);
			if (mx >= x && mx <= x + cw && my >= y0 && my <= y0 + ch) return i;
		}
		return -1;
	}

	ui void DrawMenu(double u)
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double cx = sw * 0.5;

		Txt(HudFont(), Font.CR_GOLD, String.Format(StringTable.Localize("$RR_STAGE"), stage + 1), 50 * u, 46 * u, 2.6 * u, 1.0, false);
		Txt(HudFont(), Font.CR_WHITE, ThemeName(ThemeOf(stage)), 50 * u, 96 * u, 1.8 * u, 1.0, false);
		if (defense) Txt(HudFont(), Font.CR_RED, StringTable.Localize("$RR_DEFENSE"), 50 * u, 134 * u, 1.8 * u, 1.0, false);
		Txt(HudFont(), Font.CR_RED, "DOOM RUNNER", cx, sh * 0.2, 5.0 * u);

		// play button
		double pulse = 1.0 + 0.035 * sin(phaseTime * 8.0);
		double bw = 400 * u * pulse, bh = 136 * u * pulse;
		double by = sh * 0.47;
		int hover = curInit ? MenuHit(curX, curY) : -1;
		Img("RBTN", cx - bw / 2, by - bh / 2, bw, bh);
		if (hover == 3) Screen.Dim(Color(255, 255, 255, 255), 0.18, int(cx - bw / 2), int(by - bh / 2), int(bw), int(bh));
		Txt(HudFont(), Font.CR_GOLD, StringTable.Localize("$RR_PLAY"), cx, by - 34 * u * pulse, 3.6 * u * pulse);
		Txt(NewSmallFont, Font.CR_WHITE, StringTable.Localize("$RR_MENUHELP"),
			cx, by + bh / 2 + 14 * u, 1.7 * u);

		// upgrade cards
		static const String names[] = { "$RR_UP0", "$RR_UP1", "$RR_UP2" };
		static const String icons[] = { "SHOTA0", "MGUNA0", "MEDIA0" };
		double cw = 240 * u, ch = 350 * u, gap = 26 * u;
		double x0 = cx - (cw * 3 + gap * 2) / 2;
		double y0 = sh * 0.655;
		for (int i = 0; i < 3; i++)
		{
			double x = x0 + i * (cw + gap);
			double lift = (buyFlash > 0 && buyWhich == i) ? -buyFlash * 1.2 * u : 0;
			double y = y0 + lift;
			int lvl = UpLevel(i);
			int cost = UpCost(i, lvl);
			bool afford = money >= cost;

			Img("RCARD", x, y, cw, ch);
			Txt(HudFont(), Font.CR_GOLD, StringTable.Localize(names[i]), x + cw / 2 + 8 * u, y + 24 * u, 1.35 * u);
			String cur, nxt;
			if (i == 2)
			{
				cur = String.Format("%d", int(UpVal(i, lvl)));
				nxt = String.Format("%d", int(UpVal(i, lvl + 1)));
			}
			else
			{
				cur = Dec(UpVal(i, lvl), 2);
				nxt = Dec(UpVal(i, lvl + 1), 2);
			}
			Txt(HudFont(), Font.CR_GREEN, cur, x + cw / 2, y + 62 * u, 2.4 * u);
			Icon(icons[i], x + cw / 2, y + 172 * u, 170 * u, 100 * u);
			Txt(NewSmallFont, Font.CR_DARKGREEN, "-> " .. nxt, x + cw / 2, y + 236 * u, 1.5 * u, 1.0, true, false);

			Img("RCOST", x + 16 * u, y + ch - 92 * u, cw - 32 * u, 76 * u);
			Txt(HudFont(), Font.CR_WHITE, String.Format("%d", cost), x + cw / 2 - 20 * u, y + ch - 78 * u, 2.6 * u);
			Icon(SoulFrame(), x + cw / 2 + 62 * u, y + ch - 54 * u, 56 * u, 56 * u);

			Txt(HudFont(), Font.CR_WHITE, String.Format("%d", i + 1), x + 26 * u, y + 14 * u, 1.4 * u);

			if (hover == i) Screen.Dim(Color(255, 255, 230, 160), 0.16, int(x), int(y), int(cw), int(ch));
			if (!afford) Screen.Dim(Color(255, 20, 30, 60), 0.35, int(x + 8 * u), int(y + 8 * u), int(cw - 16 * u), int(ch - 16 * u));
			if (denyFlash > 0 && buyWhich == i)
				Screen.Dim(Color(255, 255, 0, 0), denyFlash * 0.03, int(x), int(y), int(cw), int(ch));
			if (buyFlash > 0 && buyWhich == i)
				Screen.Dim(Color(255, 255, 255, 255), buyFlash * 0.03, int(x), int(y), int(cw), int(ch));
		}
	}

	ui void DrawRunHud(double u)
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double cx = sw * 0.5;

		// health bar
		double bw = 420 * u, bh = 40 * u;
		double bx = cx - bw / 2 + 30 * u, byy = 40 * u;
		Screen.Dim(Color(255, 0, 0, 0), 0.5, int(bx), int(byy), int(bw), int(bh));
		double frac = maxHp > 0 ? clamp(double(hp) / maxHp, 0.0, 1.0) : 0;
		Color hc = frac > 0.35 ? Color(255, 70, 210, 80) : Color(255, 235, 60, 60);
		Screen.Dim(hc, 0.95, int(bx + 4 * u), int(byy + 4 * u), int((bw - 8 * u) * frac), int(bh - 8 * u));
		Icon("MEDIA0", bx - 44 * u, byy + 20 * u, 64 * u, 54 * u);
		Txt(HudFont(), Font.CR_WHITE, String.Format("%d / %d", hp, maxHp), cx + 30 * u, byy + 6 * u, 1.8 * u);

		// progress
		let pm = players[consoleplayer].mo;
		if (pm && trackEnd > 0)
		{
			double pw = 520 * u;
			double px = cx - pw / 2 + 30 * u;
			double prog = clamp(pm.pos.y / trackEnd, 0.0, 1.0);
			Screen.Dim(Color(255, 255, 255, 255), 0.35, int(px), int(96 * u), int(pw), int(10 * u));
			Screen.Dim(Color(255, 255, 210, 60), 1.0, int(px), int(96 * u), int(pw * prog), int(10 * u));
		}

		// boss bar
		if (boss && !boss.dead && pm && boss.pos.y - pm.pos.y < 1700)
		{
			double w = 700 * u;
			double x = cx - w / 2;
			double y = sh - 150 * u;
			Txt(HudFont(), Font.CR_RED, StringTable.Localize("$RR_BOSS"), cx, y, 1.8 * u);
			Screen.Dim(Color(255, 0, 0, 0), 0.55, int(x), int(y + 34 * u), int(w), int(26 * u));
			double f = boss.maxhp > 0 ? clamp(boss.hp / boss.maxhp, 0.0, 1.0) : 0;
			Screen.Dim(Color(255, 230, 40, 40), 1.0, int(x + 3 * u), int(y + 37 * u), int((w - 6 * u) * f), int(20 * u));
		}

		// stats
		double sx = 34 * u;
		double sy = sh - 250 * u;
		double ls = 56 * u;
		Icon("SHOTA0", sx + 25 * u, sy + 25 * u, 56 * u, 40 * u);
		Txt(HudFont(), Font.CR_WHITE, Dec(dmg, 2), sx + 62 * u, sy + 12 * u, 1.8 * u, 1.0, false);
		Icon("MGUNA0", sx + 25 * u, sy + ls + 25 * u, 56 * u, 40 * u);
		Txt(HudFont(), Font.CR_WHITE, Dec(rate, 2) .. "/s", sx + 62 * u, sy + ls + 12 * u, 1.8 * u, 1.0, false);
		Icon("ROCKA0", sx + 25 * u, sy + ls * 2 + 25 * u, 56 * u, 40 * u);
		Txt(HudFont(), Font.CR_WHITE, Dec(range, 1), sx + 62 * u, sy + ls * 2 + 12 * u, 1.8 * u, 1.0, false);
		Icon("PLAYA1", sx + 25 * u, sy + ls * 3 + 25 * u, 56 * u, 46 * u);
		Txt(HudFont(), Font.CR_WHITE, String.Format("%d", allies.Size()), sx + 62 * u, sy + ls * 3 + 12 * u, 1.8 * u, 1.0, false);

		if (bannerTime > 0)
		{
			double ba = bannerTime > 55 ? (70 - bannerTime) / 15.0 : min(1.0, bannerTime / 15.0);
			double bs = 4.2 * u * (1.0 + 0.06 * sin(bannerTime * 20.0));
			Screen.Dim(Color(255, 120, 0, 0), 0.45 * ba, 0, int(sh * 0.3), sw, int(110 * u));
			Txt(HudFont(), Font.CR_RED, bannerText, cx, sh * 0.3 + 22 * u, bs, ba);
		}

		if (comboCount >= 3 && comboShow > 0)
		{
			double ca = min(1.0, comboShow / 10.0);
			Txt(HudFont(), Font.CR_GOLD, String.Format(StringTable.Localize("$RR_COMBOHUD"), comboCount), sw - 200 * u, 170 * u, 2.2 * u, ca);
		}

		// current weapon (bottom right)
		double wx = sw - 190 * u, wy = sh - 160 * u;
		Img("RPILL", wx - 160 * u, wy - 6 * u, 320 * u, 136 * u, 0.9);
		Icon(WIcon(weapon), wx, wy + 44 * u, 220 * u, 70 * u);
		Txt(HudFont(), Font.CR_GOLD, WName(weapon), wx, wy + 90 * u, 1.4 * u);

		if (phaseTime < 35 * 5)
		{
			double a = phaseTime < 35 * 4 ? 1.0 : (35 * 5 - phaseTime) / 35.0;
			Txt(NewSmallFont, Font.CR_WHITE, StringTable.Localize("$RR_RUNHELP"),
				cx, sh - 70 * u, 1.7 * u, a);
		}
	}

	ui void DrawResult(double u)
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double cx = sw * 0.5;
		double a = clamp(phaseTime / 20.0, 0.0, 1.0);
		Screen.Dim(Color(255, 0, 0, 0), 0.45 * a, 0, 0, sw, sh);

		if (lastWon) Txt(HudFont(), Font.CR_GREEN, StringTable.Localize("$RR_WON"), cx, sh * 0.24, 5.0 * u, a);
		else Txt(HudFont(), Font.CR_RED, StringTable.Localize("$RR_LOST"), cx, sh * 0.24, 5.0 * u, a);

		double y = sh * 0.42;
		Txt(HudFont(), Font.CR_WHITE, String.Format(StringTable.Localize("$RR_LOOT"), runCash), cx, y, 2.4 * u, a);
		if (lastWon) Txt(HudFont(), Font.CR_GOLD, String.Format(StringTable.Localize("$RR_GOAL"), lastBonus), cx, y + 60 * u, 2.4 * u, a);
		Txt(HudFont(), Font.CR_GREEN, String.Format(StringTable.Localize("$RR_TOTAL"), lastPayout), cx, y + 140 * u, 3.0 * u, a);

		if (phaseTime > 30)
		{
			double p = 0.6 + 0.4 * sin(phaseTime * 8.0);
			Txt(NewSmallFont, Font.CR_WHITE, StringTable.Localize("$RR_CONT"), cx, sh * 0.72, 2.0 * u, p);
		}
	}
}
