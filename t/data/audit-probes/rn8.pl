my $f = "/tmp/claude-0/audit/p/_rn8.tmp"; open(my $o, ">", $f); print $o "x"; close $o; my $s1 = -s $f; open($o, ">>", $f); print $o "yy"; close $o; my $s2 = -s $f; unlink $f; print "$s1 $s2\n";
