my $d="/tmp/reaudit_o03_$$"; my $a1 = -e $d ? 1 : 0; mkdir $d; my $b1 = -e $d ? 1 : 0; rmdir $d; print "$a1$b1\n";
