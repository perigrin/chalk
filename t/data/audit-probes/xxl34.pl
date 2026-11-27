our @g = (3,1,2); my $sw = 1; while ($sw) { $sw = 0; for my $i (0..$#g-1) { if ($g[$i] > $g[$i+1]) { @g[$i,$i+1] = @g[$i+1,$i]; $sw = 1 } } } print "@g\n";
