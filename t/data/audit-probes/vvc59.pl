package P; sub hi { "p$_[0]" } package Q; *hi = \&P::hi; package main; print Q->hi, Q::hi(1), "\n";
