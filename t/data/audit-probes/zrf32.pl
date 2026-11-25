my @a=(1,2); my $r=\@a; my $t=0; for my $v (@$r) { push @a,5 if @a<3; $t+=$v } print "$t\n";
