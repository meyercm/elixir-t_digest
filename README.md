# TDigest

An implementation of Ted Dunning's "t-digest", a structure for computing rank-
based statistics on large datasets.

Key features:

- smaller estimation error in the tails of the distribution
- composable (multiple t-digests can be joined into one)

For more details, see the original paper:

https://github.com/tdunning/t-digest/blob/master/docs/t-digest-paper/histo.pdf

## Use:

    iex> t = TDigest.new
    ...> t = TDigest.update(t, 1..1000)
    #TDigest<[count: 1000, clusters: 1000, delta: 0.1, p1: 10.5, p5: 50.5,
    p25: 250.5, p50: 500.5, p75: 750.5, p95: 950.5, p99: 990.5]>

Adding sequential data results in overlarge datastructures, as noted
by Dunning in his paper.  A call to `compress/1` after such an update corrects
this issue (note the reduction in number of clusters above and below 1000 -> 77):

    ...> TDigest.compress(t)
    #TDigest<[count: 1000, clusters: 77, delta: 0.1, p1: 10.5,
    p5: 50.50000000000001, p25: 250.89542483660134, p50: 500.25494225408204,
    p75: 750.6740530303031, p95: 950.5, p99: 990.5]>

With a dataset loaded, this module exposes two query methods, `percentile/2`
and `quantile/2` which are inverses of one another.

    ...> TDigest.percentile(t, 0.35)
    350.2636503460651

    ...> TDigest.quantile(t, 350)
    0.34973140759655286

The real benefit of the t-digest is the size reduction:

    iex> data = for _ <- 1..1_000_000, do: :rand.normal()
    ...> t = TDigest.new(0.1) |> TDigest.update(data)
    #TDigest<[count: 1000000, clusters: 163, delta: 0.1, p1: -2.327118447306301,
    p5: -1.6476559128477877, p25: -0.6783902616363299, p50: -0.001392334178668811,
    p75: 0.6739971826231269, p95: 1.644470629820828, p99: 2.324171666803378]>

As the inspected result shows, the t-digest is only holding 163 clusters to
represent one million observations, where each cluster is a tuple
`{center, weight}`: center is a float, and weight an integer.  Even using
Erlang's naive term format, the datastructure is only 2.4k.

    ...> :erlang.term_to_binary(t) |> byte_size
    2442

By changing the compression parameter delta, resolution and space can be traded:

    ...> t2 = TDigest.new(0.01) |> TDigest.update(data)
    #TDigest<[count: 1000000, clusters: 1344, delta: 0.01, p1: -2.3257785556861186,
    p5: -1.646212495824313, p25: -0.6766720390117584, p50: -0.0014221336729099022,
    p75: 0.672790746292638, p95: 1.6437912633928424, p99: 2.3237613045306835]>

    ...> :erlang.term_to_binary(t2) |> byte_size
    19181

### Implementation Notes:

My requirements for this datastructure don't specify performance, so the
current implementation is backed by a list of 2-tuples, rather than the
balanced tree suggested by Dunning.  The list implies most operations will be
O(n) for n clusters.  For a high-throughput use case, you may wish to choose
another data structure, or submit a pull request updating this library with a
higher performance backend.


## Installation

```elixir
def deps do
  [
    {:t_digest, "~> 0.1"},
  ]
end
```
