sub cp { my @o=@{$_[0]}; push @o,9; \@o } my @a=(1); my $r=cp(\@a); my $s=cp($r); print scalar(@a), scalar(@$r), scalar(@$s), "\n";
