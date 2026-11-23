my $f="/tmp/reaudit_o04_$$"; open(my $h,">",$f); print $h "x"; close $h; my $s = -s $f; unlink $f; my $e = -e $f ? 1:0; print "$s$e\n";
