sub cnt { my $h = shift; my $n = 0; for my $k (keys %$h) { $n++; $n += cnt($h->{$k}) if ref $h->{$k} } $n } print cnt({a=>{b=>{c=>1},d=>2},e=>3}), "\n";
