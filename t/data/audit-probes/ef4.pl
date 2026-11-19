my @log; my @s = sort { push @log, "c"; $a <=> $b } (2, 1); push @log, "after"; print "$log[0] $log[-1] @s\n";
