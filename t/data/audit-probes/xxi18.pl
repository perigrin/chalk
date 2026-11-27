our $g = 1; my $v = ${*g}; ${*g{SCALAR}} = 4; print "$v$g\n";
