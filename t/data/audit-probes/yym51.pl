my $str = join ",", map { "$_->[0]:$_->[1]" } sort { $a->[1] <=> $b->[1] or $a->[0] cmp $b->[0] } map { [$_, length] } qw(pear fig apple kiwi date); print "$str\n";
