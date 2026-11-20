my $o = {}; my $c = ref($o); if (@ARGV) { bless $o, "X" } else { bless $o, "Y" } print "$c ", ref($o), "\n";
