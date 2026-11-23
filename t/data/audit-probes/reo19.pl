sub g { local $_="g"; 1 } my @a=(1,2); for (@a) { g() } print "@a\n";
