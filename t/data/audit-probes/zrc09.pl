sub r { my ($n,$acc)=@_; push @$acc,$n; r($n-1,$acc) if $n; $acc } print "@{r(2,[])}\n";
