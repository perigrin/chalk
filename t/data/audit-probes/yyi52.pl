sub walk { my ($t,$d)=@_; return "" unless $t; walk($t->{l},$d+1) . "$t->{v}:$d " . walk($t->{r},$d+1) } my $t={v=>2,l=>{v=>1},r=>{v=>3,r=>{v=>4}}}; print walk($t,0), "\n";
