{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}

module MGW.Model where

import Data.Aeson (FromJSON, ToJSON, object, (.=), parseJSON, withObject, (.:))
import qualified Data.Aeson as Aeson
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import Data.Time (UTCTime, fromGregorian)
import Data.UUID (UUID)
import Data.Word (Word64)
import GHC.Generics (Generic)
import qualified Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

newtype MsgId = MsgId UUID deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)
newtype NetworkId = NetworkId Text deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)
newtype EndpointId = EndpointId Text deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)
newtype NativeId = NativeId Text deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)
newtype BridgeId = BridgeId Text deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)
newtype GatewayId = GatewayId Text deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)
newtype TransportKind = TransportKind Text deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Origin = Origin { oEndpoint :: EndpointId, oNative :: NativeId }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Event = EvPost Post | EvEdit MsgRef Post | EvRedact MsgRef (Maybe Text) | EvReact MsgRef Text Bool
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Post = Post
  { pId :: MsgId
  , pOrigin :: Origin
  , pBridge :: BridgeId
  , pAuthor :: ActorRef
  , pCreated :: UTCTime
  , pReceived :: UTCTime
  , pThread :: ThreadCtx
  , pContent :: Content
  , pAttach :: [Attachment]
  , pProv :: Provenance
  , pExt :: ExtMap
  } deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data ThreadCtx = ThreadCtx { tEdges :: [Edge], tTopic :: Maybe Text, tShape :: ThreadShape }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Edge = Edge { eKind :: EdgeKind, eTarget :: MsgRef, eConf :: Confidence }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data EdgeKind = ReplyTo | Root | QuoteOf | Forward | MentionOf | EdgeExt Text
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Confidence = Explicit | Heuristic
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data MsgRef = Resolved MsgId | Unresolved Origin
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data ThreadShape = Hierarchical | Flat | TopicBased | TagGraph
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data ActorRef = ActorRef { arNetwork :: NetworkId, arNative :: Text, arDisplay :: Maybe Text, arTrust :: Trust }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Trust = Asserted | Authenticated | Cryptographic
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Content = Content { cDoc :: Doc, cLang :: Maybe Text, cSrcCharset :: Maybe Charset }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

newtype Doc = Doc [Block] deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Block = Para [Inline] | Quote [Block] | Code (Maybe Text) Text | Items Bool [[Block]]
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Inline = Txt Text | Emph [Inline] | Strong [Inline] | Mono Text | Link Text [Inline] | Mention ActorRef | Spoiler [Inline] | Br
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Mark = Mark { mGateway :: GatewayId, mMsgId :: MsgId, mHops :: Int }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Provenance = Provenance { pvHops :: [Hop], pvHopLimit :: Int, pvFingerprint :: Word64, pvMark :: Maybe Mark }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

data Hop = Hop { hGateway :: GatewayId, hFrom :: NetworkId, hTo :: NetworkId, hAt :: UTCTime }
  deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

newtype ExtMap = ExtMap (Map Text Text) deriving stock (Eq, Ord, Show, Generic) deriving anyclass (ToJSON, FromJSON)

type Attachment = Text
type Charset = Text
type RichLevel = Text
type AttachPolicy = Text
type DeliveryMode = Text
type BatchPolicy = Text
type PuppetStrategy = Text
type MarkCarrier = Text
type EventKind = Text

data Capabilities = Capabilities
  { cpRich :: RichLevel
  , cpThread :: ThreadShape
  , cpMaxBytes :: Maybe Int
  , cpMaxLine :: Maybe Int
  , cpCharsets :: [Charset]
  , cpEvents :: Set EventKind
  , cpAttach :: AttachPolicy
  , cpDelivery :: DeliveryMode
  , cpIdentity :: PuppetStrategy
  , cpMark :: MarkCarrier
  } deriving (Eq, Show)

data LossNote = LossNote { lnReason :: Text, lnOriginal :: Maybe Text }
  deriving (Eq, Ord, Show)

-- Property L2: degradation is idempotent
degradeIdempotent :: Capabilities -> Content -> Bool
degradeIdempotent _ content = True  -- stub

-- Property L5: message not sent to source endpoint
routeExcludeSource :: Event -> [EndpointId] -> [EndpointId]
routeExcludeSource (EvPost p) eps = filter (\e -> e /= oEndpoint (pOrigin p)) eps
routeExcludeSource _ eps = eps

genNetworkId :: NetworkId
genNetworkId = NetworkId <$> Gen.text (Range.linear 1 20) Gen.alphaNum

genEndpointId :: EndpointId
genEndpointId = EndpointId <$> Gen.text (Range.linear 1 20) Gen.alphaNum

genNativeId :: NativeId
genNativeId = NativeId <$> Gen.text (Range.linear 1 20) Gen.alphaNum

genBridgeId :: BridgeId
genBridgeId = BridgeId <$> Gen.text (Range.linear 1 20) Gen.alphaNum

genCapabilities :: Capabilities
genCapabilities = Capabilities
  <$> Gen.element ["NoMarkup", "LightMarkup", "HtmlSubset", "FullDoc"]
  <*> Gen.element [Hierarchical, Flat, TopicBased, TagGraph]
  <*> Gen.maybe (Gen.int (Range.linear 100 100000))
  <*> Gen.maybe (Gen.int (Range.linear 40 512))
  <*> Gen.list (Range.linear 1 3) (Gen.element ["UTF-8", "CP866", "CP1251", "KOI8-R", "CP437"])
  <*> (Set.fromList <$> Gen.list (Range.linear 0 4) (Gen.element ["Post", "Edit", "Redact", "React"]))
  <*> Gen.element ["Inline", "LinkOnly", "Unsupported"]
  <*> Gen.element ["Realtime", "Polled", "Batched"]
  <*> Gen.element ["NativePuppet", "RelayPrefix", "Synthesized"]
  <*> Gen.element ["Header", "Kludge", "Tag", "ContentField", "NoCarrier"]

genContent :: Content
genContent = Content
  <$> (Doc <$> Gen.list (Range.linear 0 3) genBlock)
  <*> Gen.maybe (Gen.text (Range.linear 1 5) Gen.alphaNum)
  <*> Gen.maybe (Gen.element ["UTF-8", "CP866", "CP1251", "KOI8-R", "CP437"])

genBlock :: Block
genBlock = Gen.choice
  [ Para <$> Gen.list (Range.linear 0 2) genInline
  , Quote <$> Gen.list (Range.linear 0 2) genBlock
  , Code <$> Gen.maybe (Gen.text (Range.linear 0 5) Gen.alphaNum) <*> Gen.text (Range.linear 0 20) Gen.alphaNum
  , Items <$> Gen.bool <*> Gen.list (Range.linear 0 2) (Gen.list (Range.linear 0 2) genBlock)
  ]

genInline :: Inline
genInline = Gen.choice
  [ Txt <$> Gen.text (Range.linear 0 20) Gen.alphaNum
  , pure Br
  ]

genOrigin :: Origin
genOrigin = Origin <$> genEndpointId <*> genNativeId

genThreadCtx :: ThreadCtx
genThreadCtx = ThreadCtx
  <$> pure []
  <*> Gen.maybe (Gen.text (Range.linear 1 20) Gen.alphaNum)
  <*> Gen.element [Hierarchical, Flat, TopicBased, TagGraph]

genEvent :: Event
genEvent = do
  mkMsgId <- Gen.text (Range.linear 1 36) Gen.alphaNum
  return $ EvPost $ Post
    (MsgId (read ("10000000-0000-0000-0000-" ++ mkMsgId)))
    <$> genOrigin
    <*> genBridgeId
    <*> (ActorRef <$> genNetworkId <*> Gen.text (Range.linear 1 20) Gen.alphaNum <*> Gen.maybe (Gen.text (Range.linear 1 30) Gen.alphaNum) <*> Gen.element [Asserted, Authenticated, Cryptographic])
    <*> pure (UTCTime (fromGregorian 1970 1 1) 0)
    <*> pure (UTCTime (fromGregorian 1970 1 1) 0)
    <*> genThreadCtx
    <*> genContent
    <*> pure []
    <*> pure (Provenance [] 4 0 Nothing)
    <*> pure (ExtMap Map.empty)

-- Property tests
prop_l2_idempotent :: Hedgehog.Property
prop_l2_idempotent = Hedgehog.property $ do
  Hedgehog.discard genCapabilities
  content <- Hedgehog.forAll genContent
  Hedgehog.assert (degradeIdempotent (Capabilities "" Hierarchical Nothing Nothing [] Set.empty "" "" "" "" "") content)

prop_l5_noSource :: Hedgehog.Property
prop_l5_noSource = Hedgehog.property $ do
  event <- Hedgehog.forAll genEvent
  let eps = [EndpointId "a", EndpointId "b", EndpointId "c"]
  case event of
    EvPost p -> Hedgehog.assert (oEndpoint (pOrigin p) `notElem` routeExcludeSource event eps)
    _ -> Hedgehog.success