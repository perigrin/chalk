my $s="abc"; $s=~/(b)/; my $x=$1; { "q"=~/(q)/; } print "$x$1\n";
