sub cnt { my $n = shift; my @l = $n ? (cnt($n - 1), $n) : (); @l } my @r = cnt(3); print "@r\n";
