my @a=(1,2,3); my $l=\$a[-1]; push @a,4; $$l=0; print "@a\n";
