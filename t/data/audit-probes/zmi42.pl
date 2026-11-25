sub f { return wantarray ? (1,2) : "s" } my @a=(f(), scalar(f())); print "@a\n";
