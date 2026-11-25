sub r { my ($n)=@_; my @acc=($n); push @acc, r($n-1) if $n>0; @acc } print join(",", r(3)), "\n";
