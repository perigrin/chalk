my $f = "/tmp/claude-0/audit/p/_ef3.tmp"; unlink $f; my $a = -e $f ? 1 : 0; open(my $fh, ">", $f) or die; close $fh; my $b = -e $f ? 1 : 0; unlink $f; my $c = -e $f ? 1 : 0; print "$a$b$c\n";
