sub mk { my %h = @_; sub { $h{$_[0]} } } my $l = mk(a=>1, b=>2); print $l->("b"), "\n";
