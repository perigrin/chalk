my @a = (1,2,3); my $f = sub { $_[0] .= "x" }; $f->($_) for @a; print "@a\n";
