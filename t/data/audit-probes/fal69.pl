my $s="a,b,c"; my @o; while ($s=~s/^(\w),?//) { push @o,$1 } print "@o [$s]\n";
