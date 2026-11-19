our $g = 0; sub inc { $g++ } inc() for 1..3; my $r = $g; inc(); print "$r $g\n";
