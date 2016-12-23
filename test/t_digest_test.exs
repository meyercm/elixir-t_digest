defmodule TDigestTest do
  use ExUnit.Case

  test "new/1 gives a new digest datastructure" do
    assert %TDigest{} = TDigest.new(100)
  end
  test "new/0 defaults to 100" do
    assert %TDigest{delta: 100} = TDigest.new
  end
  test "new/1 assigns delta" do
    assert %TDigest{delta: 1000} = TDigest.new(1000)
  end
  test "count increments when adding the first item" do
    result = TDigest.new() |> TDigest.update(1)
    assert result.count == 1
  end


  describe "cluster_add" do
    test "when plenty of room in cluster, combine" do
      # simple:
      assert TDigest.cluster_add({1, 1}, 2, 1, 5) == [{1.5, 2}]
      assert TDigest.cluster_add({1, 9}, 2, 1, 100) == [{1.1, 10}]
    end
    test "when no room in cluster, add new cluster" do
      # no division:
      assert TDigest.cluster_add({1, 1}, 2, 1, 1) == [{1, 1}, {2, 1}]
      assert TDigest.cluster_add({2, 1}, 1, 1, 1) == [{1, 1}, {2, 1}]
    end
    test "when some room, split new" do
      # dividing new piece:
      assert TDigest.cluster_add({1, 9}, 2, 2, 10) == [{1.1, 10}, {2, 1}]
      assert TDigest.cluster_add({1, 9}, 0, 2, 10) == [{0, 1}, {0.9, 10}]
    end
    test "when the same, combine" do
      assert TDigest.cluster_add({1, 1}, 1, 1, 10) == [{1,2}]
    end
  end

  describe "update_clusters" do
    test "add if empty" do
      assert TDigest.update_clusters([], 0, 1.5, 1, 0.1) == [{1.5,1}]
    end
    test "adds to the front" do
      assert TDigest.update_clusters([{10, 1}], 1, 1.5, 1, 0.1) == [{1.5, 1}, {10, 1}]
      assert TDigest.update_clusters([{1.5, 1}, {10, 1}], 2, 1, 1, 0.1) == [{1, 1}, {1.5, 1}, {10, 1}]
    end
    test "adds to the rear" do
      assert TDigest.update_clusters([{1.5, 1}], 1, 10, 1, 0.1) == [{1.5, 1}, {10, 1}]
    end
    test "adds to the middle closer to front" do
      assert TDigest.update_clusters([{1.5, 1}, {10, 1}], 2, 5, 1, 0) == [{1.5, 1}, {5,1}, {10, 1}]
    end
    test "adds to the middle closer to rear" do
      assert TDigest.update_clusters([{1.5, 1}, {10, 1}], 2, 6, 1, 0) == [{1.5, 1}, {6,1}, {10, 1}]
    end
  end

  describe "quantile" do
    test "empty digest" do
      assert 0.0 == TDigest.new() |> TDigest.quantile(5)
    end
    test "smaller than" do
      result = TDigest.new
               |> TDigest.update(10)
               |> TDigest.quantile(1)
      assert result == 0
    end

    test "larger than" do
      result = TDigest.new
               |> TDigest.update(1)
               |> TDigest.quantile(10)
      assert result == 1
    end

    test "middle" do
      result = TDigest.new
               |> TDigest.update(10)
               |> TDigest.update(0)
               |> TDigest.quantile(5)
      assert result == 0.5
    end
  end

  describe "percentile" do
    test "interpolation" do
      result = TDigest.new
               |> TDigest.update(0)
               |> TDigest.update(10)
               |> TDigest.percentile(0.5)
      assert result = 5
    end
  end

end
