# Note on Dedicated Inputs
First off, it's interesting to note that the datasheet lists that this device has 32 I/Os and 12 dedicated inputs.  Across all other packages and families, no other device has more than 10 dedicated inputs.

Second, there appears to be a bug in the fitter's fuse data for a couple of the "input-only" signals.  The fitter toggles two input threshold fuses for the input on ball E1, and no fuses for the input on F8.  Neither of those makes sense to do, so most likely, one of the E1 fuses actually corresponds to the F8 ball in hardware.

Two of the "input only" pins use the same fuses as are used for regular I/O cells on the 100-TQFP package:

| 56-csBGA | 100-TQFP     |
|----------|--------------|
| ball E1? | pin 58 (C12) |
| ball E3  | pin 11 (A15) |

These fuses are very far apart in the fusemap, and the I/O cells corresponding to them in the TQFP version seem to be on opposite sides of the die, so it would be strange that they would pick these particular cells to reuse as inputs for balls that are right next to each other.  Therefore, I suspect fuse 99:159 corresponds to ball F8, and fuse 94:355 alone corresponds to ball E1, but I don't have any of these devices to validate this theory.

To be safe, it's probably best not to use the F8 input at all.

Most designs probably aren't affected by this, and even with a misconfigured input threshold, a lot of designs will probably still work fine as long as the signal's not too noisy.  So it's not too surprising to me that a bug like this could exist in the fitter and never be discovered or fixed.

