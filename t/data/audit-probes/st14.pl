my $f = sub { 1 }; my $a = ref($f); my $h = {}; my $b = ref($h); bless $h, "Z"; print "$a $b ", ref($h), "\n";
