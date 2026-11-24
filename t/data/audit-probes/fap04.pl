package C; sub set { $_[1] = "w" } package main; my $v="r"; C->set($v); print "$v\n";
