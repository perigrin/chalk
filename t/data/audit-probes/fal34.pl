our $s=""; my $r=\$s; for (1..3) { $$r.=$_; } print "$s\n";
