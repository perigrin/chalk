sub f { wantarray ? "l" : "s" } my @l = (f(), scalar(f())); my %h = (k => f()); my $r = [f()]; print "@l$h{k}$r->[0]", f() . "", "\n";
