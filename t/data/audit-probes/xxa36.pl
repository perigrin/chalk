sub f { $_[0] =~ s/a/b/; $_[0] =~ tr/b/c/ } my $x="aa"; my $n = f($x); print "$n $x\n";
