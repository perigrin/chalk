my @a=(1,2,3); my @c; for my $x (@a) { $x=9 if $x==2; push @c, "@a" } print join("|",@c),"\n";
