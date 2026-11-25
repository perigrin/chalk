my @a=("a1","b2"); for my $x (@a) { $x =~ s/(\d)/$1$1/ } print "@a\n";
