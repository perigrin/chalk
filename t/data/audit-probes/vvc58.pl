package P; sub hi { "p" } package main; *hi = \&P::hi; print hi(), "\n";
