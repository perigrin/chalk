sub f { my ($p,$r) = @_; $r->{k} = 5; "$p$_[0]" } my %h = (k=>1); print f($h{k}, \%h), "\n";
