defmodule TDigest do
  @moduledoc """

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
  another datastructure, or submit a pull request updating this library with a
  higher performance backend.

  """
  import ShorterMaps
  @default_delta
  defstruct [
    clusters: [],
    count: 0,
    delta: @default_delta,
  ]

  ####   API   ####

  @doc """
  Creates an empty T-Digest datastructure with the specified delta compression
  parameter.

      iex> TDigest.new
      #TDigest<[count: 0, clusters: 0, delta: 0.1, p1: nil, p5: nil, p25: nil,
      p50: nil, p75: nil, p95: nil, p99: nil]>
  """
  def new(delta \\ @default_delta) do
    %__MODULE__{delta: delta}
  end

  @doc """
  Adds one or more observed values to the datastructure.

  `data` can be a single value, a 2-tuple of `{value, weight}`, another
  T-Digest, or a list containing any of these.

  ## Examples:
      # adding a single value:
      iex> t = TDigest.new
      ...> t1 = TDigest.update(t, 1)
      #TDigest<[count: 1, clusters: 1, delta: 0.1, p1: 1, p5: 1, p25: 1, p50: 1,
      p75: 1, p95: 1, p99: 1]>

      # adding a list of values:
      ...> t2 = TDigest.update(t, 1..4)
      #TDigest<[count: 4, clusters: 4, delta: 0.1, p1: 1, p5: 1, p25: 1.5, p50: 2.5,
      p75: 3.5, p95: 4, p99: 4]>

      # adding a list of T-Digests:
      ...> TDigest.update(t, [t1, t2])
      #TDigest<[count: 5, clusters: 5, delta: 0.1, p1: 1, p5: 1, p25: 1.0, p50: 3,
      p75: 3.25, p95: 4, p99: 4]>

  Be sure to use `compress/1` after calling this method with sequntial data
  """
  def update(digest, data)
  def update(digest, %__MODULE__{clusters: c}), do: update(digest, c)
  def update(digest, _first.._last = range), do: update(digest, Enum.to_list(range))
  def update(digest, list) when is_list(list) do
    Enum.reduce(list, digest, fn({v, w}, d) -> update(d, v, w)
                                (v, d)      -> update(d, v)
    end)
  end
  def update(digest, value, weight \\ 1) do
    do_update(digest, value, weight)
  end


  @doc """
  Returns the value associated to a particular percentile within a distribution.
  Percentiles are given as values in the interval [0, 1], and return values are
  commensurate with the datapoints added using `update/2`.

      iex> data = for _ <- 1..1000, do: :rand.uniform(100)
      ...> t = TDigest.new |> TDigest.update(data)
      ...> TDigest.percentile(t, 0.9)
      89.9831029185868
      ...> TDigest.percentile(t, 0.5)
      48.20593708462561

  Logical inverse of `quantile/2`
  """
  def percentile(~M{clusters count}, p) do
    do_percentile(clusters, p, count, 0)
  end

  @doc """
  Returns the quantile of a particular value within a distribution.  Return
  values fall in the interval [0, 1].

      iex> data = for _ <- 1..1000, do: :rand.uniform(100)
      ...> t = TDigest.new |> TDigest.update(data)
      ...> TDigest.quantile(t, 10)
      0.10722356495468277
      ...> TDigest.quantile(t, 50)
      0.5207628183923255

  Logical inverse of `percentile/2`
  """
  def quantile(~M{clusters count}, value) do
    do_quantile(clusters, value, count, 0)
  end

  @doc """
  Compresses a T-Digest by inserting each cluster into a new T-Digest in a
  randomized order.  According to Dunning: "This final pass typically reduces
  the number of centroids by 20-40% with no apparent change in accuracy".

  Highly recommended to run once after bulk-updating with sequential data.  Repeated
  compression runs are discouraged.
  """
  def compress(digest) do
    do_compress(digest)
  end

  defimpl Inspect, for: __MODULE__ do
    import Inspect.Algebra
    @inspect_ptiles [0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99]
    def inspect(~M{count clusters delta} = digest, opts) do
      pctiles = @inspect_ptiles
                |> Enum.map(&({:"p#{round(&1 * 100)}", TDigest.percentile(digest, &1)}))
      rep = [count: count, clusters: length(clusters), delta: delta] ++ pctiles
      concat ["#TDigest<", to_doc(rep, opts), ">" ]
    end
  end

  ####   INTERNAL   ####
  @doc false
  def do_update(%__MODULE__{clusters: []} = digest, value, weight) do
    %__MODULE__{digest|clusters: [{value, weight}], count: weight}
  end
  def do_update(~M{clusters delta count} = digest, value, weight) do
    new_clusters = update_clusters(clusters, count, value, weight, delta)
    %__MODULE__{digest|clusters: new_clusters, count: count + weight}
  end

  @doc false
  def update_clusters(clusters, count, value, weight, delta, cluster_acc \\ [], q_acc \\ 0)
  #handle recursion with no leftover weight
  def update_clusters(clusters, _count, _value, 0, _delta, _c_acc, _q_acc), do: clusters

  # if it's last / only, just add it to the end
  def update_clusters([], _count, value, weight, _delta, c_acc, _q_acc) do
    [{value, weight}|c_acc]
    |> Enum.reverse
  end
  # if it's first (q_acc is still 0), just add it to the beginning
  def update_clusters([{v, _w}|_t]=clusters, _count, value, weight, _delta, _c_acc, 0)
    when v > value do
    [{value,weight}|clusters]
  end
  # we are in between the two proper clusters.., chose the closer
  def update_clusters([{v1, w1} = c1, {v2, w2} = c2|t], count, value, weight, delta, c_acc, q_acc)
    when v1 <= value and value <= v2 do
    case {value - v1, v2 - value} do
      {d1, d2} when d1 < d2 -> # closer to first centroid
        q = (q_acc + w1 / 2) / count
        lim = Enum.max([1, trunc(4 * count * delta * q * (1-q))])
        new_clusters = cluster_add(c1, value, weight, lim)
        Enum.reverse(c_acc) ++ new_clusters ++ [c2|t]
      {_d1, _d2} -> # d2 is smaller
        q = (q_acc + w1 + w2 / 2) / count
        lim = Enum.max([1, trunc(4 * count * delta * q * (1-q))])
        new_clusters = cluster_add(c2, value, weight, lim)
        Enum.reverse(c_acc) ++ [c1] ++ new_clusters ++ t
    end
  end
  # uninteresting region, recurse
  def update_clusters([{_v, w} = h|t], count, value, weight, delta, c_acc, q_acc) do
    update_clusters(t, count, value, weight, delta, [h|c_acc], q_acc + w)
  end


  @doc false
  def cluster_add({v, w}, v, weight, _limit), do: [{v, w + weight}]
  def cluster_add({v, w}, value, weight, limit) when w + weight <= limit do
    new_v = (v * w + value * weight) / (w + weight)
    [{new_v, w + weight}]
  end
  def cluster_add({v, w}, value, weight, limit) do
    rem = w - Enum.max([0, limit - weight])
    used = weight - rem
    new_v = (v * w + value * used) / (w + used)
    [{value, rem}, {new_v, w + used}]
    |> Enum.sort
  end

  @doc false
  # Easy cases:
  def do_percentile(_, bad_p, _, _) when bad_p < 0 or bad_p > 1, do: raise("percentile #{bad_p} not in [0,1]")
  def do_percentile([{v, _w}|_rest], 0, _count, _acc), do: v
  def do_percentile(list, 1, _count, _acc), do: do_percentile(Enum.reverse(list), 0, 0, 0)
  def do_percentile(_, _, 0, _), do: nil

  # actual work
  def do_percentile([{v, _w}], _p, _count, _acc), do: v
  def do_percentile([{v1, w1}, {v2, w2}|rest], p, count, acc) do
    q1 = (acc + w1 / 2) / count
    q2 = (acc + w1 + w2 / 2) / count
    cond do
      p < q1 -> v1
      q1 < p and p < q2 ->
        (v2 - v1) / (q2 - q1) * (p - q1) + v1
      true ->
        do_percentile([{v2, w2}|rest], p, count, acc + w1)
    end
  end


  @doc false
  def do_quantile(_, _, 0, _), do: 0.0
  def do_quantile([], _value, count, acc), do: acc / count
  def do_quantile([{v, _w}|_t], value, _count, 0) when value < v, do: 0
  def do_quantile([{v1, w1}, {v2, w2}|_t], value, count, acc) when v1 <= value and value <= v2 do
    q1 = (acc + w1 / 2) / count
    q2 = (acc + w1 + w2 / 2) / count
    (q2 - q1) / (v2 - v1) * (value - v1) + q1
  end
  def do_quantile([{_v, w}|t], value, count, acc), do: do_quantile(t, value, count, acc + w)


  @doc false
  def do_compress(~M{clusters delta}) do
    clusters
    |> Enum.shuffle
    |> Enum.reduce(TDigest.new(delta), fn {v, w}, d -> update(d, v, w) end)
    |> round_count
  end

  @doc false
  def round_count(~M{count}=digest), do: %{digest|count: round(count)}


end
