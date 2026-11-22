sub f { for my $x (@_) { die "f$x\n" } 1 } my $v = eval { f(1) }; print defined $v ? "v" : "u", " [$@]\n";
