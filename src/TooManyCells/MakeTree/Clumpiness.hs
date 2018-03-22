{- TooManyCells.MakeTree.Clumpiness
Gregory W. Schwartz

Collects the functions pertaining to finding the clumpiness from a single cell
dendrogram.
-}

{-# LANGUAGE PackageImports #-}
{-# LANGUAGE OverloadedStrings #-}

module TooManyCells.MakeTree.Clumpiness
    ( dendToClumpList
    , clumpToCsv
    ) where

-- Remote
import Data.Monoid ((<>))
import Data.Tree (Tree(..))
import qualified "find-clumpiness" Clumpiness as Clump
import qualified "find-clumpiness" Types as Clump
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Clustering.Hierarchical as HC
import qualified Data.Csv as CSV
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Text as T
import qualified Data.Vector as V

-- Local
import TooManyCells.MakeTree.Types
import TooManyCells.Matrix.Types

-- | Convert a single cell dendrogram to a workable format for clumpiness.
dendToClumpDend
    :: (TreeItem a)
    => LabelMap -> HC.Dendrogram (V.Vector a) -> Tree Clump.NodeLabel
dendToClumpDend (LabelMap labelMap) =
    Clump.makeWorkable
        . fmap ( Seq.fromList
               . fmap unLabel
               . V.toList
               . fmap ((\x -> Map.findWithDefault (error ("Cell has no label: " <> show x)) x labelMap) . getId)
               )

-- | Format clumpiness output to a CSV.
clumpToCsv :: [(T.Text, T.Text, Double)] -> B.ByteString
clumpToCsv = (<>) "label1,label2,value\n" . CSV.encode

-- | Get the clumpiness of the single cell labels.
dendToClumpList
    :: Clump.Exclusivity
    -> LabelMap
    -> HC.Dendrogram (V.Vector CellInfo)
    -> [(T.Text, T.Text, Double)]
dendToClumpList exclusivity labelMap =
    Clump.getClumpiness exclusivity False False
        . dendToClumpDend labelMap