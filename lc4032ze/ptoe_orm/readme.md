Row 84 indicates that pt4 is used as a PTOE and should be redirected from the cluster sum.

At first that may seem redundant, since rows 92-94 (OE mux) normally also encode that, and
for other PT routing (PTCE, PTCLK, etc.) the PT is automatically removed from the logic sum
when the mux is set to a value that requires it.  But one must remember that the OE mux is
actually associated with the I/O cell, not the macrocell, and the PTOE input to the OE mux
goes through the ORM and may be from a different MC/logic allocator.  So if row 84 didn't
exist, there would have to be a third, "reverse" channel in the ORM to propagate knowledge
of whether PTOE is used back to the original logic allocator.

This is just a quick test to validate that rows 92-94 associate to an I/O cell, while 84
stays with the MC/logic alloc, evem when the ORM is in use.
