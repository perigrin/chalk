my $cnt=0; my @s = sort { $cnt++; $a <=> $b } (3,1,2); print $cnt > 0 ? "y" : "n", "@s\n";
