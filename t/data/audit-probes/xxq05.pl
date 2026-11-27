my $x = 5; sub u { undef $_[0] } u($x); print defined $x ? "d" : "u", "\n";
