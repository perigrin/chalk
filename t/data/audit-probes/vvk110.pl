my $v = sub { my $t = shift; return "neg" if $t < 0; "pos" }->(-1); print "$v\n";
