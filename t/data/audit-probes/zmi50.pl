my @a=(1,2,3); my ($min)=sort { $a <=> $b } @a; my $max=(sort { $b <=> $a } @a)[0]; print "$min$max\n";
