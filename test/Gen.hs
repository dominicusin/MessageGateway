module MGW.Gen where

import MGW.Model
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import qualified Hedgehog as Hedgehog
import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

genMsgId :: Gen MsgId
genMsgId = MsgId <$> genUUID

genUUID :: Gen UUID
genUUID = do
  w1 <- Gen.word64 Range.linearBounded
  w2 <- Gen.word64 Range.linearBounded
  w3 <- Gen.word64 Range.linearBounded
  w4 <- Gen.word64 Range.linearBounded
  pure $ UUID.fromWords w1 w2 w3 w4

genNetworkId :: Gen NetworkId
genNetworkId = NetworkId <$> Gen.text (Range.linear 1 20) Gen.alphaNum

genEndpointId :: Gen EndpointId
genEndpointId = EndpointId <$> Gen.text (Range.linear 1 20) Gen.alphaNum

genNativeId :: Gen NativeId
genNativeId = NativeId <$> Gen.bytes (Range.linear 1 64) Gen.alphaNum

genBridgeId :: Gen BridgeId
genBridgeId = BridgeId <$> Gen.text (Range.linear 1 20) Gen.alphaNum

genTrust :: Gen Trust
genTrust = Gen.element [Asserted, Authenticated, Cryptographic]

genThreadShape :: Gen ThreadShape
genThreadShape = Gen.element [Hierarchical, Flat, TopicBased, TagGraph]

genEventKind :: Gen EventKind
genEventKind = Gen.element ["Post", "Edit", "Redact", "React"]

genCapabilities :: Gen Capabilities
genCapabilities = do
  caps <- Capabilities
    <$> Gen.element ["NoMarkup", "LightMarkup", "HtmlSubset", "FullDoc"]
    <*> genThreadShape
    <*> Gen.maybe (Gen.int (Range.linear 100 100000))
    <*> Gen.maybe (Gen.int (Range.linear 40 512))
    <*> Gen.list (Range.linear 1 3) (Gen.element ["UTF-8", "CP866", "CP1251", "KOI8-R", "CP437"])
    <*> Set.fromList <$> Gen.list (Range.linear 0 4) genEventKind
    <*> Gen.element ["Inline", "LinkOnly", "Unsupported"]
    <*> Gen.element ["Realtime", "Polled", "Batched"]
    <*> Gen.element ["NativePuppet", "RelayPrefix", "Synthesized"]
    <*> Gen.element ["Header", "Kludge", "Tag", "ContentField", "NoCarrier"]
  pure caps

genContent :: Gen Content
genContent = Content
  <$> (Doc <$> Gen.list (Range.linear 0 5) genBlock)
  <*> Gen.maybe (Gen.text (Range.linear 1 5) Gen.alphaNum)
  <*> Gen.maybe (Gen.element ["UTF-8", "CP866", "CP1251", "KOI8-R", "CP437"])

genBlock :: Gen Block
genBlock = Gen.choice
  [ Para <$> Gen.list (Range.linear 0 3) genInline
  , Quote <$> Gen.list (Range.linear 0 3) genBlock
  , Code <$> Gen.maybe (Gen.text (Range.linear 0 5) Gen.alphaNum) <*> Gen.text (Range.linear 0 20) Gen.alphaNum
  , Items <$> Gen.bool <*> Gen.list (Range.linear 0 2) (Gen.list (Range.linear 0 2) genBlock)
  ]

genInline :: Gen Inline
genInline = Gen.choice
  [ Txt <$> Gen.text (Range.linear 0 20) Gen.alphaNum
  , Emph <$> Gen.list (Range.linear 0 2) genInline
  , Strong <$> Gen.list (Range.linear 0 2) genInline
  , Mono <$> Gen.text (Range.linear 0 20) Gen.alphaNum
  , Link <$> Gen.text (Range.linear 0 20) Gen.alphaNum <*> Gen.list (Range.linear 0 2) genInline
  , Mention <$> genActorRef
  , Spoiler <$> Gen.list (Range.linear 0 2) genInline
  , pure Br
  ]

genActorRef :: Gen ActorRef
genActorRef = ActorRef
  <$> genNetworkId
  <*> Gen.text (Range.linear 1 20) Gen.alphaNum
  <*> Gen.maybe (Gen.text (Range.linear 1 30) Gen.alphaNum)
  <*> genTrust

genEdge :: Gen Edge
genEdge = Edge
  <$> genEdgeKind
  <*> genMsgRef
  <*> Gen.element [Explicit, Heuristic]

genEdgeKind :: Gen EdgeKind
genEdgeKind = Gen.choice
  [ pure ReplyTo, pure Root, pure QuoteOf, pure Forward, pure MentionOf
  , EdgeExt <$> Gen.text (Range.linear 1 10) Gen.alphaNum
  ]

genMsgRef :: Gen MsgRef
genMsgRef = Gen.choice
  [ Resolved <$> genMsgId
  , Unresolved <$> genOrigin
  ]

genOrigin :: Gen Origin
genOrigin = Origin <$> genEndpointId <*> genNativeId

genThreadCtx :: Gen ThreadCtx
genThreadCtx = ThreadCtx
  <$> Gen.list (Range.linear 0 5) genEdge
  <*> Gen.maybe (Gen.text (Range.linear 1 20) Gen.alphaNum)
  <*> genThreadShape

genProvenance :: Gen Provenance
genProvenance = Provenance
  <$> Gen.list (Range.linear 0 5) genHop
  <*> Gen.int (Range.linear 1 10)
  <*> Gen.word64 Range.linearBounded
  <*> Gen.maybe genMark

genHop :: Gen Hop
genHop = Hop
  <$> (GatewayId <$> Gen.text (Range.linear 1 10) Gen.alphaNum)
  <*> genNetworkId
  <*> genNetworkId
  <*> pure (UTCTime (fromGregorian 1970 1 1) 0)

genMark :: Gen Mark
genMark = Mark
  <$> (GatewayId <$> Gen.text (Range.linear 1 10) Gen.alphaNum)
  <*> genMsgId
  <*> Gen.int (Range.linear 0 10)

genEvent :: Gen Event
genEvent = Gen.choice
  [ EvPost <$> genPost
  , EvEdit <$> genMsgRef <*> genPost
  , EvRedact <$> genMsgRef <*> Gen.maybe (Gen.text (Range.linear 0 20) Gen.alphaNum)
  , EvReact <$> genMsgRef <*> Gen.text (Range.linear 1 5) Gen.alphaNum <*> Gen.bool
  ]

genPost :: Gen Post
genPost = Post
  <$> genMsgId
  <*> genOrigin
  <*> genBridgeId
  <*> genActorRef
  <*> pure (UTCTime (fromGregorian 1970 1 1) 0)
  <*> pure (UTCTime (fromGregorian 1970 1 1) 0)
  <*> genThreadCtx
  <*> genContent
  <*> Gen.list (Range.linear 0 3) (Gen.text (Range.linear 1 20) Gen.alphaNum)
  <*> genProvenance
  <*> pure (ExtMap Map.empty)

genExtMap :: Gen ExtMap
genExtMap = ExtMap . Map.fromList <$> Gen.list (Range.linear 0 5) ((,) <$> Gen.text (Range.linear 1 10) Gen.alphaNum <*> Gen.text (Range.linear 0 20) Gen.alphaNum)

-- L2: идемпотентность деградации
prop_l2_degrade_idempotent :: Hedgehog.Property
prop_l2_degrade_idempotent = Hedgehog.property $ do
  caps <- Hedgehog.forAll genCapabilities
  content <- Hedgehog.forAll genContent
  Hedgehog.assert (degradeIdempotent caps content)

-- L5: маршрутизация не отправляет в источник
prop_l5_route_excludes_source :: Hedgehog.Property
prop_l5_route_excludes_source = Hedgehog.property $ do
  event <- Hedgehog.forAll genEvent
  let endpoints = [EndpointId "a", EndpointId "b", EndpointId "c"]
      routed = routePure event endpoints
  case event of
    EvPost p -> Hedgehog.assert (oEndpoint (pOrigin p) `notElem` routed)
    _ -> Hedgehog.success

properties :: Hedgehog.Group
properties = Hedgehog.Group "MGW.Model"
  [ ("prop_l2_degrade_idempotent", prop_l2_degrade_idempotent)
  , ("prop_l5_route_excludes_source", prop_l5_route_excludes_source)
  ]