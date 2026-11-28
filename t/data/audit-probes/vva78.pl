our $x = 1; my $v = (local $x = 4) + 1; print "$v$x\n";
