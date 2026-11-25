my $i=0; my $s=""; { $s.=$i; last if $i++>1; redo } print "$s\n";
