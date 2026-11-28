sub f { wantarray ? () : 0 } my @l = (f(), f()); my $s = f(); print scalar(@l), "$s\n";
