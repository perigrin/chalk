my @a = (1,2,3); my $f = sub { $_[0] .= "x" }; for my $x (@a) { $f->($x) } print "@a\n";
