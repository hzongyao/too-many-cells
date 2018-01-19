{- Cluster
Gregory W. Schwartz

Collects the functions pertaining to the clustering of columns.
-}

{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE BangPatterns #-}

module Cluster
    ( hdbscan
    , clustersToClusterList
    , hClust
    , hSpecClust
    , assignClusters
    ) where

-- Remote
import Data.List (zip4)
import Data.Foldable (toList)
import Data.Int (Int32)
import Data.Maybe (catMaybes)
import H.Prelude (io)
import Language.R as R
import Language.R.QQ (r)
import Math.Clustering.Hierarchical.Spectral.Sparse (hierarchicalSpectralCluster, B (..))
import Math.Clustering.Hierarchical.Spectral.Types (clusteringTreeToDendrogram, getClusterItemsDend)
import Statistics.Quantile (continuousBy, s)
import System.IO (hPutStrLn, stderr)
import qualified Control.Lens as L
import qualified Data.Clustering.Hierarchical as HC
import qualified Data.Sequence as Seq
import qualified Data.Sparse.Common as S
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as VU
import qualified Numeric.LinearAlgebra as H

-- Local
import Types
import Utility
import Adjacency

-- | Cluster cLanguage.R.QQ (r)olumns of a sparse matrix using HDBSCAN.
hdbscan :: RMatObsRowImportant s -> R s (R.SomeSEXP s)
hdbscan (RMatObsRowImportant mat) = do
    [r| library(dbscan) |]

    clustering  <- [r| hdbscan(mat_hs, minPts = 5) |]

    return clustering

-- | Hierarchical clustering.
hClust :: SingleCells MatObsRowImportant -> ClusterResults
hClust sc =
    ClusterResults { clusterList = clustering
                   , clusterDend = cDend
                   }
  where
    cDend = fmap ( V.singleton
                 . (\ (!w, _, !y, !z)
                   -> CellInfo { barcode = w, cellRow = y, projection = z }
                   )
                 )
            dend
    clustering = assignClusters
               . fmap ( fmap ((\(!w, _, !y, !z) -> CellInfo w y z))
                      . HC.elements
                      )
               . flip HC.cutAt (findCut dend)
               $ dend
    dend = HC.dendrogram HC.CLINK items euclDist
    euclDist x y =
        sqrt . sum . fmap (** 2) $ S.liftU2 (-) (L.view L._2 y) (L.view L._2 x)
    items = (\ fs
            -> zip4
                   (V.toList $ rowNames sc)
                   fs
                   (fmap Row . take (V.length . rowNames $ sc) . iterate (+ 1) $ 0)
                   (V.toList $ projections sc)
            )
          . S.toRowsL
          . unMatObsRowImportant
          . matrix
          $ sc

-- | Assign clusters to values.
assignClusters :: [[a]] -> [(a, Cluster)]
assignClusters =
    concat . zipWith (\c -> flip zip (repeat c)) (fmap Cluster [1..])

-- | Find cut value.
findCut :: HC.Dendrogram a -> HC.Distance
findCut = continuousBy s 9 10 . VU.fromList . toList . flattenDist
  where
    flattenDist (HC.Leaf _)          = Seq.empty
    flattenDist (HC.Branch !d !l !r) =
        (Seq.<|) d . (Seq.><) (flattenDist l) . flattenDist $ r

-- | Convert the cluster object from hdbscan to a cluster list.
clustersToClusterList :: SingleCells MatObsRowImportant
                      -> R.SomeSEXP s
                      -> R s [(Cell, Cluster)]
clustersToClusterList sc clustering = do
    io . hPutStrLn stderr $ "Calculating clusters."
    clusters <- [r| clustering_hs$cluster |]
    return
        . zip (V.toList . rowNames $ sc)
        . fmap (Cluster . fromIntegral)
        $ (R.fromSomeSEXP clusters :: [Int32])

-- | Hierarchical spectral clustering
hSpecClust :: MinClusterSize -> SingleCells MatObsRow -> (ClusterResults, B)
hSpecClust (MinClusterSize minSize) sc =
    ( ClusterResults { clusterList = clustering
                     , clusterDend = dend
                     }
    , b
    )
  where
    clustering = assignClusters
               . fmap V.toList
               . getClusterItemsDend
               $ dend
    dend       = clusteringTreeToDendrogram tree
    (tree, b)  = hierarchicalSpectralCluster (Just minSize) items
               . Left
               . unMatObsRow
               . matrix
               $ sc
    items      = V.zipWith3
                    (\x y z -> CellInfo x y z)
                    (rowNames sc)
                    (fmap Row . flip V.generate id . V.length . rowNames $ sc)
                    (projections sc)