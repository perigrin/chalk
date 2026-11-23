sub mk { my @o=(1); return \@o } my $p=mk(); my $q=mk(); push @$p,2; print scalar(@$q),"\n";
