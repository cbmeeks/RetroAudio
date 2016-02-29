http://forums.parallax.com/showthread.php/122454-AY-3-8910-sound-chip?highlight=8910


Try this code for a complete runthrough of all possible AY sounds.

Code:


PUB Main | AYregisters, i, j, value, playRate

  AYregisters := AY.start( audioR, audioL ) 

  playRate := 5
  repeat
    waitcnt(cnt + 80_000_000/playrate)
    repeat i from 0 to 15
      value := (?j)&255
      if i>9 and i<13
        value &= 31
      byte[AYregisters + i] := value


