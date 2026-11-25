package P { our $v=1; sub set { $v=shift } } my $x=$P::v; P::set(4); print "$x$P::v\n";
