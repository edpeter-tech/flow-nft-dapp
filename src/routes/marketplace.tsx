import { createFileRoute, useNavigate } from '@tanstack/react-router'
import { useState, useMemo, useEffect, useRef } from 'react'
import { formatEther } from 'viem'
import { useGetAllActiveListings } from '../hooks/use-marketplace-contract'
import { NFTCard } from '../components/nft-card'
import { NFTGridSkeleton } from '../components/loading-skeleton'
import { Empty, EmptyHeader, EmptyTitle, EmptyDescription, EmptyMedia } from '../components/ui/empty'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../components/ui/select'
import { Input } from '../components/ui/input'
import { PackageOpen, Search } from 'lucide-react'
import { abis } from '../lib/contracts'
import { useBuyNFT } from '../hooks/use-marketplace-contract'

interface MarketplaceSearchParams {
  sort?: string
  collection?: string
  search?: string
}

export const Route = createFileRoute('/marketplace')({
  component: MarketplacePage,
  validateSearch: (search: Record<string, unknown>): MarketplaceSearchParams => ({
    sort: (search?.sort as string) || 'recent',
    collection: (search?.collection as string) || 'all',
    search: (search?.search as string) || '',
  }),
})

interface Listing {
  seller: string
  nftContract: string
  tokenId: bigint
  price: bigint
  active: boolean
  listedAt: bigint
}

interface NFTMetadata {
  name: string
  description: string
  image: string
}

interface EnrichedListing extends Listing {
  metadata?: NFTMetadata
  collectionName?: string
}

const ITEMS_PER_PAGE = 20

async function fetchMetadataFromURI(uri: string): Promise<NFTMetadata | null> {
  try {
    const fetchUrl = uri.startsWith('ipfs://') ? uri.replace('ipfs://', 'https://ipfs.io/ipfs/') : uri
    const response = await fetch(fetchUrl)
    if (!response.ok) throw new Error(`Failed to fetch metadata: ${response.statusText}`)
    const metadata = await response.json()
    let imageUrl = metadata.image || ''
    if (imageUrl.startsWith('ipfs://')) imageUrl = imageUrl.replace('ipfs://', 'https://ipfs.io/ipfs/')
    return { name: metadata.name || 'Unnamed NFT', description: metadata.description || '', image: imageUrl }
  } catch (error) {
    console.error('Error fetching metadata from URI:', error)
    return null
  }
}

function MarketplacePage() {
  const navigate = useNavigate({ from: '/marketplace' })
  const { sort = 'recent', collection = 'all', search = '' } = Route.useSearch()

  const [enrichedListings, setEnrichedListings] = useState<EnrichedListing[]>([])
  const [isLoadingMetadata, setIsLoadingMetadata] = useState(false)
  const [metadataCache] = useState<Map<string, NFTMetadata>>(new Map())
  const [buyingTokenId, setBuyingTokenId] = useState<bigint | null>(null)
  const [soldNFTs, setSoldNFTs] = useState<Set<string>>(new Set())
  const [modalMessage, setModalMessage] = useState<string | null>(null)
  const [confirmBuyListing, setConfirmBuyListing] = useState<EnrichedListing | null>(null)

  const offsetRef = useRef(0)
  const loadingMoreRef = useRef(false)
  const { data: listingsData, isLoading: isLoadingListings, refetch } = useGetAllActiveListings(BigInt(offsetRef.current), BigInt(ITEMS_PER_PAGE))

  // Fetch metadata
  useEffect(() => {
    async function fetchMetadataForNewListings() {
      if (!listingsData || !Array.isArray(listingsData)) return
      setIsLoadingMetadata(true)

      const listings = listingsData as Listing[]
      const enriched = await Promise.all(
        listings.map(async listing => {
          const cacheKey = `${listing.nftContract}-${listing.tokenId.toString()}`
          if (metadataCache.has(cacheKey)) return { ...listing, metadata: metadataCache.get(cacheKey) }

          try {
            const { createPublicClient, http } = await import('viem')
            const { flowTestnet } = await import('viem/chains')
            const client = createPublicClient({ chain: flowTestnet, transport: http() })

            const tokenURI = await client.readContract({
              address: listing.nftContract as `0x${string}`,
              abi: abis.nft,
              functionName: 'tokenURI',
              args: [listing.tokenId],
            }) as string

            let collectionName = ''
            try {
              collectionName = await client.readContract({
                address: listing.nftContract as `0x${string}`,
                abi: abis.nft,
                functionName: 'name',
              }) as string
            } catch {
              collectionName = `${listing.nftContract.slice(0, 6)}...${listing.nftContract.slice(-4)}`
            }

            let metadata: NFTMetadata | null = null
            if (tokenURI) metadata = await fetchMetadataFromURI(tokenURI)

            const finalMetadata: NFTMetadata = metadata || {
              name: `NFT #${listing.tokenId.toString()}`,
              description: `NFT from ${collectionName}`,
              image: `https://via.placeholder.com/400?text=NFT+${listing.tokenId.toString()}`,
            }

            metadataCache.set(cacheKey, finalMetadata)
            return { ...listing, metadata: finalMetadata, collectionName }
          } catch {
            const fallbackMetadata: NFTMetadata = {
              name: `NFT #${listing.tokenId.toString()}`,
              description: '',
              image: 'https://via.placeholder.com/400?text=NFT',
            }
            metadataCache.set(cacheKey, fallbackMetadata)
            return { ...listing, metadata: fallbackMetadata, collectionName: `${listing.nftContract.slice(0, 6)}...${listing.nftContract.slice(-4)}` }
          }
        })
      )

      setEnrichedListings(prev => {
        const merged = [...prev]
        enriched.forEach(listing => {
          const exists = merged.find(l => l.nftContract === listing.nftContract && l.tokenId === listing.tokenId)
          if (!exists) merged.push(listing)
        })
        return merged
      })

      setIsLoadingMetadata(false)
    }

    fetchMetadataForNewListings()
  }, [listingsData, metadataCache])

  const filteredAndSortedListings = useMemo(() => {
    let filtered = [...enrichedListings]
    if (collection !== 'all') filtered = filtered.filter(listing => listing.nftContract === collection)
    if (search) {
      const searchLower = search.toLowerCase()
      filtered = filtered.filter(listing => {
        const nameMatch = listing.metadata?.name?.toLowerCase().includes(searchLower)
        const tokenIdMatch = listing.tokenId.toString().includes(searchLower)
        return nameMatch || tokenIdMatch
      })
    }
    switch (sort) {
      case 'price-low':
        filtered.sort((a, b) => Number(a.price - b.price))
        break
      case 'price-high':
        filtered.sort((a, b) => Number(b.price - a.price))
        break
      case 'recent':
      default:
        filtered.sort((a, b) => Number(b.listedAt - a.listedAt))
        break
    }
    return filtered
  }, [enrichedListings, collection, search, sort])

  const handleNFTClick = (contractAddress: string, tokenId: string) => navigate({ to: '/nft/$contract/$tokenId', params: { contract: contractAddress, tokenId } })
  const { buyNFT } = useBuyNFT()

  const handleConfirmBuy = async () => {
    if (!confirmBuyListing) return
    const listing = confirmBuyListing
    const key = `${listing.nftContract}-${listing.tokenId.toString()}`

    const isSold = !listing.active || soldNFTs.has(key)
    if (isSold) {
      setModalMessage('This NFT has already been sold.')
      setConfirmBuyListing(null)
      return
    }

    setBuyingTokenId(listing.tokenId)
    try {
      await buyNFT(listing.nftContract as `0x${string}`, listing.tokenId, listing.price)
      setSoldNFTs(prev => new Set(prev).add(key))
      refetch()
    } finally {
      setBuyingTokenId(null)
      setConfirmBuyListing(null)
    }
  }

  const handleBuyClick = (listing: EnrichedListing) => {
    const key = `${listing.nftContract}-${listing.tokenId.toString()}`
    if (!listing.active || soldNFTs.has(key)) {
      setModalMessage('This NFT has already been sold.')
      return
    }
    setConfirmBuyListing(listing)
  }

  // Infinite scroll
  useEffect(() => {
    const handleScroll = () => {
      if (loadingMoreRef.current) return
      if ((window.innerHeight + window.scrollY) >= document.body.offsetHeight - 500) {
        loadingMoreRef.current = true
        offsetRef.current += ITEMS_PER_PAGE
        refetch()
        setTimeout(() => { loadingMoreRef.current = false }, 1000)
      }
    }
    window.addEventListener('scroll', handleScroll)
    return () => window.removeEventListener('scroll', handleScroll)
  }, [refetch])

  const isLoading = isLoadingListings || isLoadingMetadata

  return (
    <div className="container mx-auto px-4 py-8">
      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-4 mb-8">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search by name or token ID..."
            value={search}
            onChange={e => navigate({ search: prev => ({ ...prev, search: e.target.value }) })}
            className="pl-9"
          />
        </div>
        <Select value={collection} onValueChange={value => navigate({ search: prev => ({ ...prev, collection: value }) })}>
          <SelectTrigger className="w-full sm:w-[200px]"><SelectValue placeholder="All Collections" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All Collections</SelectItem>
            {Array.from(new Set(enrichedListings.map(l => l.nftContract))).map(addr => (
              <SelectItem key={addr} value={addr}>{addr.slice(0, 6)}...{addr.slice(-4)}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={sort} onValueChange={value => navigate({ search: prev => ({ ...prev, sort: value }) })}>
          <SelectTrigger className="w-full sm:w-[200px]"><SelectValue placeholder="Sort by" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="recent">Recently Listed</SelectItem>
            <SelectItem value="price-low">Price: Low to High</SelectItem>
            <SelectItem value="price-high">Price: High to Low</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Loading / Empty */}
      {isLoading && <NFTGridSkeleton count={ITEMS_PER_PAGE} />}
      {!isLoading && filteredAndSortedListings.length === 0 && (
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon"><PackageOpen className="h-6 w-6" /></EmptyMedia>
            <EmptyTitle>No NFTs found</EmptyTitle>
            <EmptyDescription>{search || collection !== 'all' ? 'Try adjusting filters or search terms' : 'No NFTs listed at the moment'}</EmptyDescription>
          </EmptyHeader>
        </Empty>
      )}

      {/* NFT Grid */}
      {!isLoading && filteredAndSortedListings.length > 0 && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6 mb-8">
          {filteredAndSortedListings.map(listing => {
            const key = `${listing.nftContract}-${listing.tokenId.toString()}`
            const isBuying = buyingTokenId === listing.tokenId
            const isSold = !listing.active || soldNFTs.has(key)
            return (
              <div key={key} className="flex flex-col gap-3">
                <NFTCard
                  contractAddress={listing.nftContract}
                  tokenId={listing.tokenId.toString()}
                  name={listing.metadata?.name || `NFT #${listing.tokenId.toString()}`}
                  image={listing.metadata?.image || 'https://via.placeholder.com/400?text=NFT'}
                  price={formatEther(listing.price)}
                  collectionName={listing.collectionName}
                  isListed={true}
                  onClick={() => navigate({ to: '/nft/$contract/$tokenId', params: { contract: listing.nftContract, tokenId: listing.tokenId.toString() } })}
                />
                <button
                  onClick={() => handleBuyClick(listing)}
                  disabled={isBuying}
                  className="w-full py-2 rounded-lg bg-black text-white text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isSold ? 'Sold' : isBuying ? 'Processing...' : `Buy for ${formatEther(listing.price)} FLOW`}
                </button>
              </div>
            )
          })}
        </div>
      )}

      {/* Confirmation Modal */}
      {confirmBuyListing && (
        <div className="fixed inset-0 flex items-center justify-center z-50 bg-black bg-opacity-50">
          <div className="bg-white rounded-xl p-6 w-80 text-center shadow-lg">
            <h2 className="text-lg font-bold mb-4">Confirm Purchase</h2>
            <img src={confirmBuyListing.metadata?.image} className="w-40 h-40 object-cover mb-4 mx-auto rounded-lg" />
            <p className="mb-2 font-semibold">{confirmBuyListing.metadata?.name}</p>
            <p className="mb-4 text-sm text-gray-500">Price: {formatEther(confirmBuyListing.price)} FLOW</p>
            <div className="flex justify-between gap-4">
              <button className="flex-1 py-2 bg-gray-300 rounded-lg" onClick={() => setConfirmBuyListing(null)}>Cancel</button>
              <button className="flex-1 py-2 bg-black text-white rounded-lg" onClick={handleConfirmBuy}>Confirm</button>
            </div>
          </div>
        </div>
      )}

      {/* Info Modal */}
      {modalMessage && (
        <div className="fixed inset-0 flex items-center justify-center z-50 bg-black bg-opacity-50">
          <div className="bg-white rounded-xl p-6 w-80 text-center shadow-lg">
            <h2 className="text-lg font-bold mb-4">Notice</h2>
            <p className="mb-6">{modalMessage}</p>
            <button className="px-4 py-2 bg-black text-white rounded-lg" onClick={() => setModalMessage(null)}>OK</button>
          </div>
        </div>
      )}
    </div>
  )
}

export default MarketplacePage
