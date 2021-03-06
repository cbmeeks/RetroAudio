{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                    AYcog - AY-3-891X / YM2149 emulator V0.10 (C) 2010-05 Johannes Ahlebrand                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                    TERMS OF USE: Parallax Object Exchange License                                            │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}
CON

  PSG_FREQ          = 2_200_000.0  ' Clock frequency input to the chip   (Colour Genie EG2000 computer runs at 2.2Mhz)

' Unmark these lines for AY setup
'{
  REGISTER_OFFSET  = 3
  LONG_CORRECTION  = 0
  DUMMY_VARIABLE   = 0
'}

' Unmark these lines YM setup
{
  REGISTER_OFFSET  = 1
  LONG_CORRECTION  = 2
  DUMMY_VARIABLE   = 1
}

 ' WARNING !!
 ' Don't alter the constants below unless you know what you are doing
 '-------------------------------------------------------------------
  SAMPLE_RATE      = 60_000                 ' Sample rate of AYcog
  OSC_CORR         = trunc(2.133 * PSG_FREQ)' Calibrates the relative oscillator frequency
  NOISE_CORR       = OSC_CORR>>1            ' Calibrates the relative noise frequency
  ENV_CORR         = OSC_CORR>>9            ' Calibrates the relative envelope timing

PUB start(right,left)
  arg1 := $18000000 | left
  arg2 := $18000000 | right
  r1 := ((1<<right) | (1<<left))&!1
  sampleRate := clkfreq/SAMPLE_RATE
  cog := cognew(@AYEMU, @AYregisters) + 1
  return @AYregisters

PUB stop
  if cog
    cogstop(cog~ -1)

dat org 0
'
'                Assembly AY emulator
'
AYEMU
              mov      AY_Address, par                      ' Setup everyting
              add      AY_Address, #LONG_CORRECTION
              mov      dira, r1
              mov      ctra, arg1
              mov      ctrb, arg2
              mov      waitCounter, cnt
              add      waitCounter, sampleRate
'----------------------------------------------------------- 
mainLoop      call     #getRegisters
              call     #AY                                  ' Main loop
              call     #mixer
              jmp      #mainLoop

'
' Read all AY registers from hub memory and convert
' them to more convenient representations.
'
getRegisters  mov       tempValue, AY_Address
              rdword    frequency1, tempValue               ' Read in all 4
              shl       frequency1, #20                     ' frequency registers
              add       tempValue,  #2                      ' and make them "32 bits"
              rdword    frequency2, tempValue
              shl       frequency2, #20
              add       tempValue,  #2
              rdword    frequency3, tempValue
              shl       frequency3, #20
              add       tempValue,  #2
              rdbyte    noisePeriod, tempValue
              and       noisePeriod, #$1f
              add       tempValue, #1                       ' Read in some more
              rdbyte    enableRegister, tempValue           ' registers
              min       noisePeriod, #3
              add       tempValue, #REGISTER_OFFSET
              rdbyte    amplitude1, tempValue
              shl       amplitude1, #10
              add       tempValue, #1
              rdbyte    amplitude2, tempValue
              shl       amplitude2, #10
              add       tempValue, #1
              rdbyte    amplitude3, tempValue
              shl       amplitude3, #10
              add       tempValue, #3
              rdlong    envelopePeriod, tempValue           '────
              shl       envelopePeriod, #8
              andn      envelopePeriod, mask16bit           '────
              rdbyte    envelopeShape, tempValue
              shl       noisePeriod, #20
getRegisters_ret ret

'
' Calculate AY samples channel 1-3 and store in out1-out3
'
AY

'───────────────────────────────────────────────────────────
'───────────────────────────────────────────────────────────
'        Envelope shaping -> envelopeAmplitude
'───────────────────────────────────────────────────────────
Envelope      sub      envCounter, envSubValue           wc ' Handles envelope incrementing
  if_c        add      envCounter, envelopePeriod
  if_c        add      envelopeValue, envelopeInc
'───────────────────────────────────────────────────────────
              test     envelopeShape, #16                wz ' Handle envelope reset bit ( Extra bit added by Ahle2 )
  if_nz       neg      envelopeValue, #0
  if_nz       mov      envelopeInc, #1
  if_nz       mov      envCounter, envelopePeriod
  if_nz       and      envelopeShape, #15
  if_nz       wrbyte   envelopeShape, tempValue             '<-IMPORTANT, resets bit 5 in hub ram
'───────────────────────────────────────────────────────────
              test     envelopeShape, #8                 wc ' Handle continue = 0
              test     envelopeShape, #4                 wz
 if_nc_and_z  mov      envelopeShape, #9
 if_nc_and_nz mov      envelopeShape, #15
'───────────────────────────────────────────────────────────
              test     envelopeShape, #2                 wz ' Sets the envelope hold level
              muxz     envHoldLevel, #15                    '
'───────────────────────────────────────────────────────────
              test     envelopeValue, #16                wz ' Check if > 15
              test     envelopeShape, #1                 wc ' Check hold bit
  if_nz_and_c mov      envelopeInc, #0                      ' Hold envelope
  if_nz_and_c mov      envelopeValue, envHoldLevel          '
'───────────────────────────────────────────────────────────
  if_nz       test     envelopeShape, #2                 wc ' Check and handle alternate
  if_nz_and_c neg      envelopeInc, envelopeInc
  if_nz_and_c add      envelopeValue, envelopeInc
'───────────────────────────────────────────────────────────
              mov      arg1, envelopeValue
              test     envelopeShape, #4                 wc ' Check and handle invertion (attack)
  if_c        xor      arg1, #15
'───────────────────────────────────────────────────────────
              and      arg1, #15
              add      arg1, #amplitudeTable                ' Lookup the amplitude according
              movs     :indexed1, arg1                      ' to the current state of the envelope
              nop
:indexed1     mov      envelopeAmplitude, 0


'───────────────────────────────────────────────────────────
'───────────────────────────────────────────────────────────
'     Waveform shaping noise -> bit 7 of enableRegister
'       (this "trick" gains some cycles per sample)
'───────────────────────────────────────────────────────────
Noise1        sub      phaseAccumulatorN, noiseSubValue  wc ' Noise generator
  if_c        add      phaseAccumulatorN, noisePeriod
  if_c        add      noiseValue, noiseAdd
  if_c        ror      noiseValue, #15
              test     noiseValue, val31bit              wc
              muxc     enableRegister, #128                 ' <- This spares some cycles later on

'───────────────────────────────────────────────────────────
'───────────────────────────────────────────────────────────
'            Waveform shaping channel 1 -> out1
'───────────────────────────────────────────────────────────
Square1       sub      phaseAccumulator1, oscSubValue    wc ' Square wave generator
  if_c        add      phaseAccumulator1, frequency1        ' channel 1
  if_c        xor      oscValue1, #1
              test     oscValue1, #1                     wc
              muxc     enableRegister, #64                  ' This spares instructions
'───────────────────────────────────────────────────────────
              test     enableRegister, #65               wz ' Handles mixing of channel 1
              muxz     arg1, mask16bit                      ' Tone on/off, Noice on/off
              test     enableRegister, #136              wz
  if_z        mov      arg1, mask16bit                      ' arg1 = (ToneOn | ToneDisable) & (NoiseOn | NoiseDisable)
'───────────────────────────────────────────────────────────
Env1          test     amplitude1, val14bit              wz ' Selects envelope or fixed amplitude
  if_nz       mov      amplitude1, envelopeAmplitude        ' depending on bit 5 of amplitude register 1
'───────────────────────────────────────────────────────────
Amp1          sub      arg1, val15bit                       ' Calculate sample
              mov      arg2, amplitude1                     ' out1 = waveform * amplitude
              call     #multiply
              mov      out1, r1

'───────────────────────────────────────────────────────────
'─────────────────────────────────────────────────────────── 
'            Waveform shaping channel 2 -> out2
'───────────────────────────────────────────────────────────
Square2       sub      phaseAccumulator2, oscSubValue    wc ' Square wave generator
  if_c        add      phaseAccumulator2, frequency2        ' channel 2
  if_c        xor      oscValue2, mask32bit
              test     oscValue2, #1                     wc
              muxc     enableRegister, #64                  ' This spares instructions
'───────────────────────────────────────────────────────────
              test     enableRegister, #66               wz ' Handles mixing of channel 2
              muxz     arg1, mask16bit                      ' Tone on/off, Noice on/off
              test     enableRegister, #144              wz
  if_z        mov      arg1, mask16bit                      ' arg1 = (ToneOn | ToneDisable) & (NoiseOn | NoiseDisable)
'───────────────────────────────────────────────────────────
Env2          test     amplitude2, val14bit              wz ' Selects envelope or fixed amplitude
  if_nz       mov      amplitude2, envelopeAmplitude        ' depending on bit 5 of amplitude register 2
'───────────────────────────────────────────────────────────
Amp2          sub      arg1, val15bit                       ' Calculate sample
              mov      arg2, amplitude2                     ' out2 = waveform * amplitude
              call     #multiply
              mov      out2, r1

'───────────────────────────────────────────────────────────
'───────────────────────────────────────────────────────────              
'            Waveform shaping channel 3 -> out3
'─────────────────────────────────────────────────────────── 
Square3       sub      phaseAccumulator3, oscSubValue    wc ' Square wave generator
  if_c        add      phaseAccumulator3, frequency3        ' channel 3
  if_c        xor      oscValue3, mask32bit
              test     oscValue3, #1                     wc
              muxc     enableRegister, #64                  ' This spares even more instructions
'───────────────────────────────────────────────────────────
              test     enableRegister, #68               wz ' Handles mixing of channel 2
              muxz     arg1, mask16bit                      ' Tone on/off, Noice on/off
              test     enableRegister, #160              wz
  if_z        mov      arg1, mask16bit                      ' arg1 = (ToneOn | ToneDisable) & (NoiseOn | NoiseDisable)
'───────────────────────────────────────────────────────────
Env3          test     amplitude3, val14bit              wz ' Selects envelope or fixed amplitude
  if_nz       mov      amplitude3, envelopeAmplitude        ' depending on bit 5 of amplitude register 3
'───────────────────────────────────────────────────────────
Amp3          sub      arg1, val15bit                       ' Calculate sample
              mov      arg2, amplitude3                     ' out3 = waveform * amplitude
              call     #multiply
              mov      out3, r1
AY_ret        ret

' 
'      Mix channels and update FRQA/FRQB PWM-values
'
mixer         mov      r1, out1
              add      r1, out2
              add      r1, out3
              add      r1, val31bit                        '  DC offset
              waitcnt  waitCounter, sampleRate             '  Wait until the right time to update
              mov      FRQA, r1                            '| Update PWM values in FRQA/FRQB
              mov      FRQB, r1                            '|
mixer_ret     ret


' 
'    Multiplication     r1(I32) = arg1(I32) * arg2(I32)
'
multiply      mov       r1,   #0            'Clear 32-bit product
:multiLoop    shr       arg2, #1   wc, wz   'Half multiplyer and get LSB of it
  if_c        add       r1,   arg1          'Add multiplicand to product on C
              shl       arg1, #1            'Double multiplicand    
  if_nz       jmp       #:multiLoop         'Check nonzero multiplier to continue multiplication
              mov       arg1, #0
multiply_ret  ret



' 
'    Variables, tables, masks and reference values
'
amplitudeTable      long 16384
                    long 10922
                    long 7281
                    long 4854
                    long 3236
                    long 2157
                    long 1438
                    long 958
                    long 639
                    long 426
                    long 284
                    long 189
                    long 126
                    long 84
                    long 56
                    long 37

'Masks and reference values    
mask32bit           long $ffffffff
mask16bit           long $ffff
val31bit            long $80000000
val15bit            long $8000
val14bit            long $4000
noiseAdd            long $88008800 'Value to add to the noise generator every noise update
sampleRate          long 0

'Setup and subroutine parameters  
arg1                long 0
arg2                long 0
r1                  long 0
AY_Address          long 0

'AY variables
envCounter          long 1
envSubValue         long ENV_CORR
oscSubValue         long OSC_CORR
noiseSubValue       long NOISE_CORR
envelopeValue       long 0
envelopeInc         long 1
envHoldLevel        res  1
oscValue1           res  1
oscValue2           res  1
oscValue3           res  1
amplitude1          res  1
amplitude2          res  1
amplitude3          res  1
envelopeAmplitude   res  1
enableRegister      res  1
envelopeShape       res  1
frequency1          res  1
frequency2          res  1
frequency3          res  1
envelopePeriod      res  1
noisePeriod         res  1
phaseAccumulatorN   res  1
phaseAccumulator1   res  1
phaseAccumulator2   res  1
phaseAccumulator3   res  1
noiseValue          res  1
noiseOut            res  1
out1                res  1
out2                res  1
out3                res  1
waitCounter         res  1
tempValue           res  1
                    fit                          

VAR
  word cog[2]
  word dummy[DUMMY_VARIABLE]
  word AYregisters[8]

�