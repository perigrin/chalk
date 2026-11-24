my $s="abc"; $s=~/b/g; my $p=pos($s); $s=~/c/g; print $p, pos($s), "\n";
