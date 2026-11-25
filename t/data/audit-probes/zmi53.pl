my $s="hello world"; (my $t=$s)=~s/(\w+)/\u$1/g; my $n=($s=~s/o/0/g); my $c=($s=~tr/l//); print "$t|$s|$n$c\n";
